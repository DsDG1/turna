package me.dsdogs.turna.anki.reviewer

import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileInputStream

class OfficialAnkiMediaHandler(
    private val mediaRoot: File,
    private val assetLoader: (String) -> ByteArray?,
) {
    fun intercept(request: WebResourceRequest): WebResourceResponse {
        val uri = request.url
        if (!OfficialAnkiMediaPath.originAllowed(uri.scheme, uri.host, uri.port)) {
            return denied(403, if (uri.host != OfficialAnkiMediaPath.ORIGIN_HOST) "host" else "origin")
        }
        val encodedPath = uri.encodedPath ?: return denied(404, "path")
        val target = OfficialAnkiMediaPath.classifyEncodedPath(encodedPath)
        if (!target.allowed) {
            return denied(403, target.reason ?: "denied")
        }
        if (target.assetName != null) {
            val bytes = assetLoader(target.assetName) ?: return missingAsset(target.assetName)
            return bytesResponse(OfficialAnkiMime.mimeForName(target.assetName), bytes)
        }
        val name = target.mediaName ?: return denied(403, "media_name")
        val file = resolveMediaFile(name) ?: return denied(403, "escape")
        if (!file.isFile) return denied(404, "missing")
        return fileResponse(request, file)
    }

    fun resolveMediaFile(rawName: String): File? =
        OfficialAnkiMediaStore.resolveMediaFile(mediaRoot, rawName)

    private fun fileResponse(request: WebResourceRequest, file: File): WebResourceResponse {
        val mime = OfficialAnkiMime.mimeForName(file.name)
        val encoding = OfficialAnkiMime.encodingForMime(mime)
        val length = file.length()
        val rangeHeader = request.requestHeaders["Range"] ?: request.requestHeaders["range"]
        val range = OfficialAnkiHttpRange.parse(rangeHeader, length)
        val cors = corsHeaders()
        if (!range.satisfiable) {
            val extra = cors.toMutableMap()
            extra["Content-Range"] = range.contentRange
            extra["Content-Length"] = "0"
            extra["Accept-Ranges"] = "bytes"
            extra["Cache-Control"] = "private, max-age=0"
            extra["X-Content-Type-Options"] = "nosniff"
            return WebResourceResponse(
                mime,
                encoding,
                416,
                "Range Not Satisfiable",
                extra,
                ByteArrayInputStream(ByteArray(0)),
            )
        }
        val headers = cors.toMutableMap()
        headers["Accept-Ranges"] = "bytes"
        headers["Cache-Control"] = "private, max-age=0"
        headers["Content-Length"] = range.contentLength.toString()
        if (range.status == 206) {
            headers["Content-Range"] = range.contentRange
        }
        if (mime == "application/octet-stream") {
            headers["X-Content-Type-Options"] = "nosniff"
        }
        val method = request.method.uppercase()
        if (method == "HEAD") {
            return WebResourceResponse(
                mime,
                encoding,
                range.status,
                if (range.status == 206) "Partial Content" else "OK",
                headers,
                ByteArrayInputStream(ByteArray(0)),
            )
        }
        val stream = FileInputStream(file)
        if (range.start > 0) {
            var skipped = 0L
            while (skipped < range.start) {
                val n = stream.skip(range.start - skipped)
                if (n <= 0) break
                skipped += n
            }
        }
        val limited = LimitedInputStream(stream, range.contentLength)
        return WebResourceResponse(
            mime,
            encoding,
            range.status,
            if (range.status == 206) "Partial Content" else "OK",
            headers,
            limited,
        )
    }

    private fun bytesResponse(mime: String, bytes: ByteArray): WebResourceResponse {
        val encoding = OfficialAnkiMime.encodingForMime(mime)
        val headers = corsHeaders().toMutableMap()
        headers["Content-Length"] = bytes.size.toString()
        headers["Cache-Control"] = "no-store"
        headers["Content-Security-Policy"] = OfficialAnkiWebPolicy.CSP
        if (mime == "application/octet-stream") {
            headers["X-Content-Type-Options"] = "nosniff"
        }
        return WebResourceResponse(
            mime,
            encoding,
            200,
            "OK",
            headers,
            ByteArrayInputStream(bytes),
        )
    }

    private fun missingAsset(name: String): WebResourceResponse {
        val reason = if (name.contains("mathjax") || name.endsWith("tex-svg-full.js")) {
            "MATHJAX_ASSET_MISSING"
        } else {
            "asset_missing"
        }
        return denied(404, reason)
    }

    private fun denied(code: Int, reason: String): WebResourceResponse {
        return WebResourceResponse(
            "text/plain",
            "utf-8",
            code,
            reason,
            mapOf(
                "Cache-Control" to "no-store",
                "Content-Length" to "0",
                "X-Content-Type-Options" to "nosniff",
            ),
            ByteArrayInputStream(ByteArray(0)),
        )
    }

    private fun corsHeaders(): Map<String, String> = mapOf(
        "Access-Control-Allow-Origin" to "null",
        "Accept-Ranges" to "bytes",
    )

    companion object {
        fun isSafeAssetName(name: String): Boolean = OfficialAnkiMediaPath.isSafeAssetName(name)

        fun mimeForName(name: String): String = OfficialAnkiMime.mimeForName(name)

        fun isDeniedExternal(uri: android.net.Uri): Boolean {
            val scheme = uri.scheme?.lowercase() ?: return true
            if (scheme == "https" && uri.host == OfficialAnkiWebPolicy.ORIGIN_HOST) return false
            return true
        }
    }
}
