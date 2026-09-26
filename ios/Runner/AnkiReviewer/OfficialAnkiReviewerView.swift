import Foundation
import Flutter
import WebKit

/// One active present at a time; a newer request completes the previous
/// Flutter result with RENDER_SUPERSEDED. Direct port of the Android
/// PresentAckCoordinator.
final class PresentAckCoordinator {
    struct Request {
        let id: Int64
        let generation: Int64
        let side: String
    }

    struct PresentResult {
        var ok: Bool
        var code: String? = nil
        var generation: Int64? = nil
        var side: String? = nil
        var height: Double? = nil
        var recoverable: Bool = false

        var map: [String: Any?] {
            [
                "ok": ok,
                "code": code ?? "",
                "generation": generation as Any,
                "side": side ?? "",
                "height": height ?? 0.0,
                "recoverable": recoverable,
            ]
        }
    }

    static let codeSuperseded = "RENDER_SUPERSEDED"

    private var nextId: Int64 = 0
    private var active: Request?
    private var lastHeightGeneration: Int64 = 0
    private(set) var lastHeight: Double = 0

    func begin(generation: Int64, side: String, completeOld: (PresentResult) -> Void) -> Request {
        if let previous = active {
            completeOld(PresentResult(
                ok: false,
                code: Self.codeSuperseded,
                generation: previous.generation,
                side: previous.side,
                recoverable: true
            ))
        }
        nextId += 1
        let request = Request(id: nextId, generation: generation, side: side)
        active = request
        return request
    }

    func isActive(_ requestId: Int64) -> Bool { active?.id == requestId }
    func activeRequest() -> Request? { active }

    func shouldPublishHeight(generation: Int64, height: Double) -> Bool {
        let activeGeneration = active?.generation ?? lastHeightGeneration
        if generation < lastHeightGeneration || generation < activeGeneration {
            return false
        }
        lastHeightGeneration = generation
        lastHeight = height
        return true
    }

    func complete(requestId: Int64, result: PresentResult) -> PresentResult? {
        guard let current = active, current.id == requestId else { return nil }
        active = nil
        var result = result
        let gen = result.generation ?? current.generation
        if result.ok, let height = result.height {
            if !shouldPublishHeight(generation: gen, height: height) {
                result.height = lastHeight
            }
        }
        return result
    }

    func cancel(requestId: Int64, result: PresentResult) -> PresentResult? {
        guard isActive(requestId) else { return nil }
        active = nil
        return result
    }
}

/// WKWebView implementation of the official Anki reviewer. Mirrors the Android
/// platform view: same MethodChannel name/methods, same JS entry points
/// (window.OfficialReviewer, window.__turnaLastRender poll), same ack flow.
final class OfficialAnkiReviewerView: NSObject, FlutterPlatformView {
    private static let tag = "OfficialAnkiReviewer"
    private static let applyLimit = 200
    private static let pollLimit = 400
    private static let applyDelay: TimeInterval = 0.05
    private static let presentDeadline: TimeInterval = 20
    private static let nightBackground = UIColor(red: 0x11 / 255.0, green: 0x11 / 255.0, blue: 0x11 / 255.0, alpha: 1)

    private let webView: WKWebView
    private let channel: FlutterMethodChannel
    private let diagnostics: Bool
    private var readySent = false
    private var disposed = false
    private var pendingPayload: [String: Any]?
    private var pendingSide = "question"
    private var applyAttempts = 0
    private var pollCount = 0
    private var waitingResult: FlutterResult?
    private var applying = false
    private var presentDeadlineToken: Int64 = 0
    private let presentAck = PresentAckCoordinator()

    init(frame: CGRect, messenger: FlutterBinaryMessenger, viewId: Int64, params: [String: Any]?, assetLoader: @escaping (String) -> Data?) {
        let mediaRoot = URL(fileURLWithPath: params?["mediaRoot"] as? String ?? "")
        diagnostics = params?["diagnostics"] as? Bool ?? false
        let textZoom = params?["textZoom"] as? Int ?? 100

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.allowsInlineMediaPlayback = true
        if #available(iOS 15.0, *) {
            let prefs = WKWebpagePreferences()
            prefs.allowsContentJavaScript = true
            config.defaultWebpagePreferences = prefs
        }
        config.setURLSchemeHandler(
            OfficialAnkiSchemeHandler(mediaRoot: mediaRoot, assetLoader: assetLoader),
            forURLScheme: OfficialAnkiSchemeHandler.scheme
        )

        // Text-only zoom, applied to every frame (the card iframe is sandboxed
        // so the shell cannot reach into it — a user script covers both).
        let zoomScript = WKUserScript(
            source: "document.documentElement.style.webkitTextSizeAdjust='\(Self.clampZoom(textZoom))%';",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(zoomScript)

        webView = WKWebView(frame: frame, configuration: config)
        channel = FlutterMethodChannel(
            name: "me.dsdogs.turna/official_anki_reviewer_\(viewId)",
            binaryMessenger: messenger
        )

        super.init()

        webView.backgroundColor = (params?["theme"] as? String) == "night" ? Self.nightBackground : .white
        webView.isOpaque = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        channel.setMethodCallHandler { [weak self] call, result in
            self?.onMethodCall(call, result: result)
        }
        webView.load(URLRequest(url: URL(string: OfficialAnkiSchemeHandler.shellURL)!))
    }

    func view() -> UIView { webView }

    // MARK: - MethodChannel

    private func onMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setCard":
            pendingPayload = cardPayload(call)
            pendingSide = "question"
            startPresent(result)
        case "showQuestion":
            pendingSide = "question"
            startPresent(result)
        case "showAnswer":
            pendingSide = "answer"
            startPresent(result)
        case "present":
            pendingPayload = cardPayload(call)
            pendingSide = (call.arguments as? [String: Any])?["side"] as? String ?? "question"
            startPresent(result)
        case "setTheme":
            let theme = (call.arguments as? [String: Any])?["theme"] as? String ?? "day"
            eval("window.OfficialReviewer && OfficialReviewer.setTheme(\(Self.jsString(theme)))")
            result(nil)
        case "setTextZoom":
            let zoom = call.arguments as? Int ?? 100
            setTextZoom(zoom)
            result(nil)
        case "clearCard":
            pendingPayload = nil
            eval("window.OfficialReviewer && OfficialReviewer.clearCard()")
            result(nil)
        case "dispose":
            dispose()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func cardPayload(_ call: FlutterMethodCall) -> [String: Any] {
        let args = call.arguments as? [String: Any] ?? [:]
        return [
            "cardId": args["cardId"] ?? 0,
            "generation": args["generation"] ?? 0,
            "questionDisplayHtml": args["questionDisplayHtml"] as? String ?? "",
            "answerDisplayHtml": args["answerDisplayHtml"] as? String ?? "",
            "css": args["css"] as? String ?? "",
            "theme": args["theme"] as? String ?? "day",
            "comparisonHtml": args["comparisonHtml"] as? String ?? "",
            "templateOrdinal": args["templateOrdinal"] ?? 0,
            "bodyClass": args["bodyClass"] as? String ?? "card card1",
        ]
    }

    private static func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json
    }

    private static func clampZoom(_ zoom: Int) -> Int {
        min(max(zoom, 100), 200)
    }

    /// Android applies WebSettings.textZoom to every frame; the sandboxed card
    /// iframe is unreachable from the shell here, so the frame half travels
    /// over the existing postMessage channel (card-frame.js listens for
    /// turnaTextZoom).
    private func setTextZoom(_ zoom: Int) {
        let value = "\(Self.clampZoom(zoom))%"
        eval("""
            (function(){ var v = \(Self.jsString(value));
              document.documentElement.style.webkitTextSizeAdjust = v;
              var f = document.getElementById('card-frame');
              if (f && f.contentWindow) {
                f.contentWindow.postMessage({ v: 1, type: 'turnaTextZoom', zoom: v }, '*');
              }
              return 'ok'; })()
        """)
    }

    // MARK: - present / ack flow (mirrors OfficialAnkiReviewerPlatformView)

    private func startPresent(_ result: @escaping FlutterResult) {
        let generation = (pendingPayload?["generation"] as? Int64)
            ?? Int64((pendingPayload?["generation"] as? Int) ?? 0)
            ?? ((pendingPayload?["generation"] as? NSNumber)?.int64Value ?? 0)
        let request = presentAck.begin(generation: generation, side: pendingSide) { [weak self] superseded in
            guard let self else { return }
            let pending = self.waitingResult
            self.waitingResult = nil
            self.applying = false
            pending?(superseded.map)
        }
        waitingResult = result
        applyAttempts = 0
        pollCount = 0
        applying = false
        armDeadline(request.id)
        applyPending(request.id)
    }

    private func armDeadline(_ requestId: Int64) {
        presentDeadlineToken += 1
        let token = presentDeadlineToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.presentDeadline) { [weak self] in
            guard let self, token == self.presentDeadlineToken else { return }
            if self.presentAck.isActive(requestId) {
                self.finishTimeout(requestId, code: "RENDER_TIMEOUT")
            }
        }
    }

    private func applyPending(_ requestId: Int64) {
        if disposed || !presentAck.isActive(requestId) || applying { return }
        guard let payload = pendingPayload else {
            eval("(function(){ return window.OfficialReviewer ? 'ready' : 'not_ready'; })()") { [weak self] value in
                guard let self, self.presentAck.isActive(requestId) else { return }
                let raw = value ?? ""
                if raw != "ready" && self.applyAttempts < Self.applyLimit {
                    self.applyAttempts += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.applyDelay) { [weak self] in
                        self?.applyPending(requestId)
                    }
                    return
                }
                if raw != "ready" {
                    self.finishTimeout(requestId, code: "SHELL_NOT_READY")
                    return
                }
                self.notifyReady()
                self.finishPresent(requestId, result: PresentAckCoordinator.PresentResult(ok: true, side: "ready"))
            }
            return
        }
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadJson = String(data: payloadData, encoding: .utf8) else {
            finishTimeout(requestId, code: "RENDER_TIMEOUT")
            return
        }
        let side = Self.jsString(pendingSide)
        // Do not await present()'s Promise — WKWebView serializes it as {}
        // which would be misread as a timeout. The ack arrives via
        // __turnaLastRender polling instead.
        let script = "(function(){ if (!window.OfficialReviewer) return 'not_ready'; " +
            "window.__turnaLastRender = null; " +
            "OfficialReviewer.present(\(payloadJson), \(side)); return 'started'; })()"
        applying = true
        eval(script) { [weak self] value in
            guard let self, self.presentAck.isActive(requestId) else { return }
            let raw = value ?? ""
            if raw != "started" {
                self.applying = false
                if self.applyAttempts < Self.applyLimit {
                    self.applyAttempts += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.applyDelay) { [weak self] in
                        self?.applyPending(requestId)
                    }
                } else {
                    self.finishTimeout(requestId, code: "SHELL_NOT_READY")
                }
                return
            }
            self.notifyReady()
            self.pollCount = 0
            self.pollCompletion(requestId)
        }
    }

    private func pollCompletion(_ requestId: Int64) {
        if disposed { return }
        guard presentAck.isActive(requestId) else {
            applying = false
            return
        }
        eval("(function(){ var a = window.__turnaLastRender; return a ? JSON.stringify(a) : ''; })()") { [weak self] value in
            guard let self, self.presentAck.isActive(requestId) else {
                self?.applying = false
                return
            }
            let raw = value ?? ""
            if raw.hasPrefix("{") && raw.contains("\"type\"") {
                let type = Self.jsonType(raw)
                // cardAccepted / frameReady are mid-present markers; only
                // renderComplete / renderError finish the request.
                if type == "cardAccepted" || type == "frameReady" {
                    if self.pollCount < Self.pollLimit {
                        self.pollCount += 1
                        self.schedulePoll(requestId)
                        return
                    }
                } else if type == "renderComplete" || type == "renderError" {
                    self.applying = false
                    self.completeFromJs(requestId, raw: raw)
                    return
                }
            }
            if self.pollCount < Self.pollLimit {
                self.pollCount += 1
                self.schedulePoll(requestId)
            } else {
                self.applying = false
                self.finishTimeout(requestId, code: "RENDER_TIMEOUT")
            }
        }
    }

    private func schedulePoll(_ requestId: Int64) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.applyDelay) { [weak self] in
            self?.pollCompletion(requestId)
        }
    }

    private static func jsonType(_ raw: String) -> String {
        guard let keyRange = raw.range(of: "\"type\""),
              let colon = raw[keyRange.upperBound...].firstIndex(of: ":") else { return "" }
        let rest = raw[raw.index(after: colon)...]
        guard let firstQuote = rest.firstIndex(of: "\"") else { return "" }
        let afterQuote = rest[rest.index(after: firstQuote)...]
        guard let secondQuote = afterQuote.firstIndex(of: "\"") else { return "" }
        return String(afterQuote[..<secondQuote])
    }

    private func completeFromJs(_ requestId: Int64, raw: String) {
        guard let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            finishTimeout(requestId, code: "RENDER_TIMEOUT")
            return
        }
        let height = (parsed["height"] as? NSNumber)?.doubleValue ?? 0
        let generation = (parsed["generation"] as? NSNumber)?.int64Value
        if height > 0, presentAck.shouldPublishHeight(generation: generation ?? 0, height: height) {
            channel.invokeMethod("pageHeightChanged", arguments: height)
        }
        var code = parsed["stableCode"] as? String ?? ""
        if code.isEmpty { code = parsed["code"] as? String ?? "" }
        let type = parsed["type"] as? String ?? ""
        let ok = type == "renderComplete"
        if !ok {
            channel.invokeMethod("renderError", arguments: code.isEmpty ? "RENDER_TIMEOUT" : code)
        }
        finishPresent(requestId, result: PresentAckCoordinator.PresentResult(
            ok: ok,
            code: code.isEmpty ? (ok ? nil : "RENDER_TIMEOUT") : code,
            generation: generation,
            side: (parsed["side"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? pendingSide,
            height: height,
            recoverable: !ok
        ))
    }

    private func finishTimeout(_ requestId: Int64, code: String) {
        applying = false
        guard presentAck.isActive(requestId) else { return }
        channel.invokeMethod("renderError", arguments: code)
        finishPresent(requestId, result: PresentAckCoordinator.PresentResult(
            ok: false, code: code, recoverable: true
        ))
    }

    private func finishPresent(_ requestId: Int64, result: PresentAckCoordinator.PresentResult) {
        guard let completed = presentAck.complete(requestId: requestId, result: result) else { return }
        let pending = waitingResult
        waitingResult = nil
        pending?(completed.map)
    }

    private func notifyReady() {
        if readySent || disposed { return }
        readySent = true
        channel.invokeMethod("ready", arguments: nil)
    }

    private func onShellFinished() {
        notifyReady()
        if pendingPayload != nil, waitingResult != nil, presentAck.activeRequest() != nil, !applying,
           let active = presentAck.activeRequest() {
            applyPending(active.id)
        }
    }

    private func eval(_ script: String, callback: ((String?) -> Void)? = nil) {
        if disposed { return }
        webView.evaluateJavaScript(script) { value, _ in
            callback?(value as? String)
        }
    }

    private func dispose() {
        if disposed { return }
        disposed = true
        presentDeadlineToken += 1
        applying = false
        channel.setMethodCallHandler(nil)
        if let leftover = waitingResult {
            waitingResult = nil
            leftover([
                "ok": false,
                "code": PresentAckCoordinator.codeSuperseded,
                "recoverable": true,
            ])
        }
        webView.stopLoading()
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }
}

// MARK: - WKNavigationDelegate / WKUIDelegate (mirrors OfficialAnkiReviewerClient + WebPolicy)

extension OfficialAnkiReviewerView: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
            return
        }
        if let url = url, url.scheme == OfficialAnkiSchemeHandler.scheme,
           url.host == OfficialAnkiSchemeHandler.originHost {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.url?.absoluteString == OfficialAnkiSchemeHandler.shellURL
            || webView.url?.absoluteString.hasPrefix(OfficialAnkiSchemeHandler.shellURL + "?") == true {
            onShellFinished()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        channel.invokeMethod("renderError", arguments: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        channel.invokeMethod("renderError", arguments: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Never open windows/popups from card content.
        nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(false)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        completionHandler(nil)
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }
}
