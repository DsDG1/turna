import Foundation
import WebKit

/// Serves the reviewer shell, its JS/CSS/MathJax assets, and collection media
/// over the `turna-anki://anki.local` origin — the iOS mirror of the Android
/// `shouldInterceptRequest` handler (WKWebView cannot intercept https://, so
/// text assets are rewritten https://anki.local -> turna-anki://anki.local at
/// serve time and CSP/base/postMessage targets stay internally consistent).
final class OfficialAnkiSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "turna-anki"
    static let originHost = "anki.local"
    static let origin = "\(scheme)://\(originHost)"
    static let shellURL = "\(origin)/assets/reviewer.html"
    static let assetPrefix = "/assets/"
    static let mediaPrefix = "/media/"

    /// Same CSP as Android's OfficialAnkiCsp.VALUE, retargeted to the custom
    /// scheme. Also injected as a response header on asset responses.
    static let csp =
        "default-src 'none'; " +
        "img-src \(origin) data: blob:; " +
        "media-src \(origin) data: blob:; " +
        "font-src \(origin) data:; " +
        "style-src 'unsafe-inline' \(origin); " +
        "script-src 'unsafe-inline' \(origin); " +
        "connect-src 'none'; " +
        "frame-src \(origin); " +
        "object-src 'none'; " +
        "base-uri \(origin)/media/; " +
        "form-action 'none';"

    /// Rewrites the https://anki.local literals baked into the shared assets
    /// (CSP meta, <base>, script src, postMessage targetOrigin) for the iOS
    /// custom-scheme origin.
    static let retargetFrom = "https://anki.local"
    static let retargetTo = origin

    private let mediaRoot: URL
    private let assetLoader: (String) -> Data?

    init(mediaRoot: URL, assetLoader: @escaping (String) -> Data?) {
        self.mediaRoot = mediaRoot
        self.assetLoader = assetLoader
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let request = urlSchemeTask.request
        guard let url = request.url,
              url.scheme == Self.scheme,
              url.host == Self.originHost else {
            finish(urlSchemeTask, status: 403, mime: "text/plain", headers: deniedHeaders())
            return
        }
        // url.path is already percent-decoded once (percentEncodedPath needs
        // iOS 16; deployment target is 15.0), so the media name below is
        // decoded exactly once — decoding again would corrupt filenames that
        // legitimately contain %XX (e.g. a stored "rate%20.png").
        let requestPath = url.path
        if requestPath.hasPrefix(Self.assetPrefix) {
            let name = String(requestPath.dropFirst(Self.assetPrefix.count))
            guard Self.isSafeAssetName(name) else {
                finish(urlSchemeTask, status: 403, mime: "text/plain", headers: deniedHeaders())
                return
            }
            guard let raw = assetLoader(name) else {
                finish(urlSchemeTask, status: 404, mime: "text/plain", headers: deniedHeaders())
                return
            }
            var bytes = raw
            let mime = Self.mime(for: name)
            if mime.hasPrefix("text/") || mime == "application/json" || mime == "text/javascript" || mime == "image/svg+xml" {
                if var text = String(data: bytes, encoding: .utf8) {
                    text = text.replacingOccurrences(of: Self.retargetFrom, with: Self.retargetTo)
                    bytes = Data(text.utf8)
                }
            }
            var headers = corsHeaders()
            headers["Content-Length"] = String(bytes.count)
            headers["Cache-Control"] = "no-store"
            headers["Content-Security-Policy"] = Self.csp
            if mime == "application/octet-stream" {
                headers["X-Content-Type-Options"] = "nosniff"
            }
            finish(urlSchemeTask, status: 200, mime: mime, headers: headers, body: bytes)
            return
        }
        guard requestPath.hasPrefix(Self.mediaPrefix) else {
            finish(urlSchemeTask, status: 403, mime: "text/plain", headers: deniedHeaders())
            return
        }
        let mediaName = String(requestPath.dropFirst(Self.mediaPrefix.count))
        guard Self.isSafeMediaName(mediaName) else {
            finish(urlSchemeTask, status: 403, mime: "text/plain", headers: deniedHeaders())
            return
        }
        guard let file = resolveMediaFile(mediaName) else {
            finish(urlSchemeTask, status: 404, mime: "text/plain", headers: deniedHeaders())
            return
        }
        serveFile(urlSchemeTask, request: request, file: file)
    }

    // MARK: - media path safety (mirrors OfficialAnkiMediaPath/Store)

    /// Validates an already-decoded media filename (url.path arrives decoded
    /// once): rejects separators, dot segments, absolute paths and residual
    /// encoded traversal left by double-encoding.
    static func isSafeMediaName(_ name: String) -> Bool {
        if name.isEmpty || name.contains("\u{0}") { return false }
        if name.contains("/") || name.contains("\\") { return false }
        if name == "." || name == ".." { return false }
        if name.hasPrefix("/") { return false }
        if name.range(of: "^[A-Za-z]:", options: .regularExpression) != nil { return false }
        let lower = name.lowercased()
        if lower.contains("%2f") || lower.contains("%5c") ||
            lower.contains("%00") || lower.contains("%2e%2e") {
            return false
        }
        return true
    }

    static func isSafeAssetName(_ name: String) -> Bool {
        if name.isEmpty || name.hasPrefix("/") { return false }
        if name.split(separator: "/").contains("..") { return false }
        if name.contains("//") { return false }
        return name.range(of: "^[A-Za-z0-9._/-]+$", options: .regularExpression) != nil
    }

    private func resolveMediaFile(_ name: String) -> URL? {
        let root = mediaRoot.resolvingSymlinksInPath()
        let candidate = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        let resolved = candidate.resolvingSymlinksInPath()
        var rootPath = root.path
        if !rootPath.hasSuffix("/") { rootPath += "/" }
        if resolved != root && !resolved.path.hasPrefix(rootPath) { return nil }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir)
        if isDir.boolValue { return nil }
        return resolved
    }

    // MARK: - responses (mirrors OfficialAnkiMediaHandler + OfficialAnkiHttpRange)

    /// Card media can be video-sized — stream bounded chunks on a worker queue
    /// instead of buffering the whole file into one Data.
    private static let streamChunk = 256 * 1024
    private let streamQueue = DispatchQueue(label: "turna.anki.media-stream", qos: .userInitiated)
    private let streamLock = NSLock()
    private var streams: [ObjectIdentifier: StreamState] = [:]

    private final class StreamState {
        var cancelled = false
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask)
        streamLock.lock()
        streams[key]?.cancelled = true
        streamLock.unlock()
    }

    /// Delivers response/chunks/finish only while the task is alive; WebKit
    /// forbids touching the task after stop(), so each send is checked under
    /// the same lock that stop() takes.
    private func streamSend(_ task: WKURLSchemeTask, _ stream: StreamState, response: HTTPURLResponse? = nil, data: Data? = nil) -> Bool {
        streamLock.lock()
        defer { streamLock.unlock() }
        if stream.cancelled { return false }
        if let response { task.didReceive(response) }
        if let data { task.didReceive(data) }
        return true
    }

    private func streamFinish(_ task: WKURLSchemeTask, _ stream: StreamState) {
        streamLock.lock()
        defer { streamLock.unlock() }
        if !stream.cancelled { task.didFinish() }
    }

    private func deliverFile(_ task: WKURLSchemeTask, file: URL, range: ByteRange, mime: String, headers: [String: String], stream: StreamState) {
        var responseHeaders = headers
        responseHeaders["Content-Type"] = mime
        guard let url = task.request.url,
              let response = HTTPURLResponse(url: url, statusCode: range.status, httpVersion: "HTTP/1.1", headerFields: responseHeaders) else {
            return
        }
        guard streamSend(task, stream, response: response) else { return }
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            streamLock.lock()
            let alive = !stream.cancelled
            streamLock.unlock()
            if alive { task.didFailWithError(URLError(.cannotOpenFile)) }
            return
        }
        defer { try? handle.close() }
        if range.start > 0 { try? handle.seek(toOffset: UInt64(range.start)) }
        var remaining = range.contentLength
        while remaining > 0 {
            guard let chunk = try? handle.read(upToCount: min(Self.streamChunk, Int(remaining))), !chunk.isEmpty else { break }
            if !streamSend(task, stream, data: chunk) { return }
            remaining -= Int64(chunk.count)
        }
        streamFinish(task, stream)
    }

    private func serveFile(_ urlSchemeTask: WKURLSchemeTask, request: URLRequest, file: URL) {
        let mime = Self.mime(for: file.lastPathComponent)
        let length = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        let rangeHeader = request.allHTTPHeaderFields?["Range"] ?? request.allHTTPHeaderFields?["range"]
        let range = Self.parseRange(rangeHeader, length: length)
        var headers = corsHeaders()
        headers["Accept-Ranges"] = "bytes"
        headers["Cache-Control"] = "private, max-age=0"
        if !range.satisfiable {
            headers["Content-Range"] = range.contentRange
            headers["Content-Length"] = "0"
            headers["X-Content-Type-Options"] = "nosniff"
            finish(urlSchemeTask, status: 416, mime: mime, headers: headers, body: Data())
            return
        }
        headers["Content-Length"] = String(range.contentLength)
        if range.status == 206 {
            headers["Content-Range"] = range.contentRange
        }
        if mime == "application/octet-stream" {
            headers["X-Content-Type-Options"] = "nosniff"
        }
        if (request.httpMethod ?? "GET").uppercased() == "HEAD" {
            finish(urlSchemeTask, status: range.status, mime: mime, headers: headers, body: Data())
            return
        }
        let stream = StreamState()
        let key = ObjectIdentifier(urlSchemeTask)
        streamLock.lock()
        streams[key] = stream
        streamLock.unlock()
        streamQueue.async { [self] in
            defer {
                streamLock.lock()
                streams.removeValue(forKey: key)
                streamLock.unlock()
            }
            deliverFile(urlSchemeTask, file: file, range: range, mime: mime, headers: headers, stream: stream)
        }
    }

    private func finish(_ task: WKURLSchemeTask, status: Int, mime: String, headers: [String: String], body: Data = Data()) {
        var responseHeaders = headers
        responseHeaders["Content-Type"] = mime
        guard let url = task.request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: responseHeaders) else {
            return
        }
        task.didReceive(response)
        if !body.isEmpty { task.didReceive(body) }
        task.didFinish()
    }

    private func deniedHeaders() -> [String: String] {
        ["Cache-Control": "no-store", "Content-Length": "0", "X-Content-Type-Options": "nosniff"]
    }

    private func corsHeaders() -> [String: String] {
        // The card iframe is sandboxed (opaque origin) so media responses must
        // explicitly allow the "null" origin, same as on Android.
        ["Access-Control-Allow-Origin": "null", "Accept-Ranges": "bytes"]
    }

    // MARK: - range parsing (mirrors OfficialAnkiHttpRange)

    struct ByteRange {
        let satisfiable: Bool
        let start: Int64
        let end: Int64
        let length: Int64
        let status: Int
        var contentLength: Int64 { satisfiable && end >= start ? end - start + 1 : 0 }
        var contentRange: String { satisfiable ? "bytes \(start)-\(end)/\(length)" : "bytes */\(length)" }
    }

    static func parseRange(_ header: String?, length: Int64) -> ByteRange {
        func unsatisfiable() -> ByteRange { ByteRange(satisfiable: false, start: 0, end: -1, length: length, status: 416) }
        func full() -> ByteRange { ByteRange(satisfiable: true, start: 0, end: length <= 0 ? -1 : length - 1, length: length, status: 200) }
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return full() }
        guard header.lowercased().hasPrefix("bytes=") else { return unsatisfiable() }
        let spec = String(header.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        if spec.isEmpty || spec.contains(",") { return unsatisfiable() }
        guard let dash = spec.firstIndex(of: "-") else { return unsatisfiable() }
        let left = spec[..<dash].trimmingCharacters(in: .whitespaces)
        let right = spec[spec.index(after: dash)...].trimmingCharacters(in: .whitespaces)
        if length <= 0 { return unsatisfiable() }
        if left.isEmpty && right.isEmpty { return unsatisfiable() }
        if left.isEmpty {
            guard let suffix = Int64(right), suffix > 0 else { return unsatisfiable() }
            let start = length > suffix ? length - suffix : 0
            return ByteRange(satisfiable: true, start: start, end: length - 1, length: length, status: 206)
        }
        guard let start = Int64(left), start >= 0, start < length else { return unsatisfiable() }
        let end: Int64
        if right.isEmpty {
            end = length - 1
        } else {
            guard let e = Int64(right), e >= start else { return unsatisfiable() }
            end = e >= length ? length - 1 : e
        }
        return ByteRange(satisfiable: true, start: start, end: end, length: length, status: 206)
    }

    // MARK: - mime (mirrors OfficialAnkiMime)

    static func mime(for name: String) -> String {
        let lower = name.lowercased()
        if lower.hasSuffix(".png") { return "image/png" }
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
        if lower.hasSuffix(".gif") { return "image/gif" }
        if lower.hasSuffix(".webp") { return "image/webp" }
        if lower.hasSuffix(".svg") { return "image/svg+xml" }
        if lower.hasSuffix(".mp3") { return "audio/mpeg" }
        if lower.hasSuffix(".ogg") { return "audio/ogg" }
        if lower.hasSuffix(".wav") { return "audio/wav" }
        if lower.hasSuffix(".m4a") { return "audio/mp4" }
        if lower.hasSuffix(".mp4") { return "video/mp4" }
        if lower.hasSuffix(".webm") { return "video/webm" }
        if lower.hasSuffix(".css") { return "text/css" }
        if lower.hasSuffix(".js") { return "text/javascript" }
        if lower.hasSuffix(".html") { return "text/html" }
        if lower.hasSuffix(".json") { return "application/json" }
        if lower.hasSuffix(".woff") { return "font/woff" }
        if lower.hasSuffix(".woff2") { return "font/woff2" }
        if lower.hasSuffix(".ttf") { return "font/ttf" }
        if lower.hasSuffix(".otf") { return "font/otf" }
        return "application/octet-stream"
    }
}
