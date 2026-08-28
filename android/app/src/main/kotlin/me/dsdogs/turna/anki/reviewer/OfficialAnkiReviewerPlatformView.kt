package me.dsdogs.turna.anki.reviewer

import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.ConsoleMessage
import android.webkit.GeolocationPermissions
import android.webkit.JsPromptResult
import android.webkit.JsResult
import android.webkit.PermissionRequest
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.json.JSONObject
import java.io.File

class OfficialAnkiReviewerPlatformView(
    context: android.content.Context,
    messenger: BinaryMessenger,
    viewId: Int,
    creationParams: Map<*, *>?,
    private val assetLoader: (String) -> ByteArray?,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val webView = WebView(context)
    private val channel = MethodChannel(
        messenger,
        "me.dsdogs.turna/official_anki_reviewer_$viewId",
    )
    private val mainHandler = Handler(Looper.getMainLooper())
    private var readySent = false
    private var disposed = false
    private val diagnostics = creationParams?.get("diagnostics") == true
    private val mediaRoot = File(creationParams?.get("mediaRoot") as? String ?: "")
    private val initialTextZoom = (creationParams?.get("textZoom") as? Int) ?: 100
    private var pendingPayload: JSONObject? = null
    private var pendingSide: String = "question"
    private var applyAttempts = 0
    private var pollCount = 0
    private var waitingResult: MethodChannel.Result? = null
    private var applying = false
    private var presentDeadlineToken = 0L
    private val presentAck = PresentAckCoordinator()

    init {
        channel.setMethodCallHandler(this)
        // Seed the native surface with the theme so a night-mode session
        // never flashes white before the shell paints its own background.
        webView.setBackgroundColor(
            if (creationParams?.get("theme") == "night") NIGHT_BACKGROUND else Color.WHITE,
        )
        webView.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        OfficialAnkiWebPolicy.apply(webView, diagnostics, initialTextZoom)
        val handler = OfficialAnkiMediaHandler(mediaRoot, assetLoader)
        webView.webViewClient = OfficialAnkiReviewerClient(
            handler,
            onReady = { onShellFinished() },
            onError = { message ->
                Log.e(TAG, "webview error $message")
                channel.invokeMethod("renderError", message)
            },
        )
        webView.webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: android.os.Message?,
            ): Boolean = false

            override fun onJsAlert(
                view: WebView?,
                url: String?,
                message: String?,
                result: JsResult?,
            ): Boolean {
                result?.cancel()
                return true
            }

            override fun onJsConfirm(
                view: WebView?,
                url: String?,
                message: String?,
                result: JsResult?,
            ): Boolean {
                result?.cancel()
                return true
            }

            override fun onJsPrompt(
                view: WebView?,
                url: String?,
                message: String?,
                defaultValue: String?,
                result: JsPromptResult?,
            ): Boolean {
                result?.cancel()
                return true
            }

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?,
            ): Boolean {
                filePathCallback?.onReceiveValue(null)
                return true
            }

            override fun onGeolocationPermissionsShowPrompt(
                origin: String?,
                callback: GeolocationPermissions.Callback?,
            ) {
                callback?.invoke(origin, false, false)
            }

            override fun onPermissionRequest(request: PermissionRequest) {
                request.deny()
            }

            override fun onConsoleMessage(consoleMessage: ConsoleMessage): Boolean {
                if (diagnostics) {
                    Log.i(TAG, "console ${consoleMessage.message()}")
                    val text = consoleMessage.message().take(200)
                    channel.invokeMethod("consolePolicyViolation", text)
                }
                return true
            }
        }
        webView.setDownloadListener { _, _, _, _, _ -> }
        webView.loadUrl(OfficialAnkiWebPolicy.SHELL_URL)
    }

    override fun getView(): View = webView

    override fun dispose() {
        if (disposed) return
        disposed = true
        presentDeadlineToken += 1
        applying = false
        mainHandler.removeCallbacksAndMessages(null)
        channel.setMethodCallHandler(null)
        val leftover = waitingResult
        waitingResult = null
        leftover?.success(
            mapOf(
                "ok" to false,
                "code" to PresentAckCoordinator.CODE_SUPERSEDED,
                "recoverable" to true,
            ),
        )
        webView.stopLoading()
        webView.loadUrl("about:blank")
        webView.destroy()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setCard" -> {
                pendingPayload = cardPayload(call)
                pendingSide = "question"
                startPresent(result)
            }
            "showQuestion" -> {
                pendingSide = "question"
                startPresent(result)
            }
            "showAnswer" -> {
                pendingSide = "answer"
                startPresent(result)
            }
            "present" -> {
                pendingPayload = cardPayload(call)
                pendingSide = call.argument<String>("side") ?: "question"
                startPresent(result)
            }
            "setTheme" -> {
                val theme = call.argument<String>("theme") ?: "day"
                eval("window.OfficialReviewer && OfficialReviewer.setTheme(${JSONObject.quote(theme)})")
                result.success(null)
            }
            "setTextZoom" -> {
                // WebSettings-level text scaling: effective immediately for the
                // shell and card iframe, no re-present required.
                val zoom = (call.arguments as? Int) ?: 100
                webView.settings.textZoom = zoom.coerceIn(100, 200)
                result.success(null)
            }
            "clearCard" -> {
                pendingPayload = null
                eval("window.OfficialReviewer && OfficialReviewer.clearCard()")
                result.success(null)
            }
            "dispose" -> {
                dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun cardPayload(call: MethodCall): JSONObject {
        val payload = JSONObject()
        payload.put("cardId", call.argument<Any>("cardId") ?: 0)
        payload.put("generation", call.argument<Any>("generation") ?: 0)
        payload.put("questionDisplayHtml", call.argument<String>("questionDisplayHtml") ?: "")
        payload.put("answerDisplayHtml", call.argument<String>("answerDisplayHtml") ?: "")
        payload.put("css", call.argument<String>("css") ?: "")
        payload.put("theme", call.argument<String>("theme") ?: "day")
        payload.put("comparisonHtml", call.argument<String>("comparisonHtml") ?: "")
        payload.put("templateOrdinal", call.argument<Any>("templateOrdinal") ?: 0)
        payload.put("bodyClass", call.argument<String>("bodyClass") ?: "card card1")
        return payload
    }

    private fun onShellFinished() {
        notifyReady()
        val active = presentAck.activeRequest()
        if (pendingPayload != null && waitingResult != null && active != null && !applying) {
            Log.i(TAG, "shell ready, flush present requestId=${active.id}")
            applyPending(active.id)
        }
    }

    private fun notifyReady() {
        if (readySent || disposed) return
        readySent = true
        channel.invokeMethod("ready", null)
    }

    private fun startPresent(result: MethodChannel.Result) {
        val generation = pendingPayload?.optLong("generation") ?: 0L
        val request = presentAck.begin(generation, pendingSide) { superseded ->
            val pending = waitingResult
            waitingResult = null
            applying = false
            pending?.success(superseded.toMap())
        }
        waitingResult = result
        applyAttempts = 0
        pollCount = 0
        applying = false
        armDeadline(request.id)
        Log.i(TAG, "startPresent requestId=${request.id} gen=$generation")
        applyPending(request.id)
    }

    private fun armDeadline(requestId: Long) {
        val token = ++presentDeadlineToken
        mainHandler.postDelayed({
            if (token != presentDeadlineToken) return@postDelayed
            if (!presentAck.isActive(requestId)) return@postDelayed
            Log.w(TAG, "present deadline requestId=$requestId attempts=$applyAttempts")
            finishTimeout(requestId, "RENDER_TIMEOUT")
        }, PRESENT_DEADLINE_MS)
    }

    private fun applyPending(requestId: Long) {
        if (disposed) return
        if (!presentAck.isActive(requestId)) return
        if (applying) return
        val payload = pendingPayload
        if (payload == null) {
            eval("(function(){ return window.OfficialReviewer ? 'ready' : 'not_ready'; })()") { value ->
                if (!presentAck.isActive(requestId)) return@eval
                val raw = unwrapJs(value)
                if (raw != "ready" && applyAttempts < APPLY_LIMIT) {
                    applyAttempts += 1
                    mainHandler.postDelayed({ applyPending(requestId) }, APPLY_DELAY_MS)
                    return@eval
                }
                if (raw != "ready") {
                    finishTimeout(requestId, "SHELL_NOT_READY")
                    return@eval
                }
                notifyReady()
                finishPresent(
                    requestId,
                    PresentAckCoordinator.PresentResult(ok = true, side = "ready"),
                )
            }
            return
        }
        val side = JSONObject.quote(pendingSide)
        // Do not await the present() Promise here. This WebView serializes a
        // pending Promise as "{}", which we used to treat as RENDER_TIMEOUT.
        val script =
            "(function(){ if (!window.OfficialReviewer) return 'not_ready'; " +
                "window.__turnaLastRender = null; " +
                "OfficialReviewer.present($payload, $side); return 'started'; })()"
        applying = true
        Log.i(TAG, "apply present requestId=$requestId attempt=$applyAttempts")
        eval(script) { value ->
            if (!presentAck.isActive(requestId)) {
                applying = false
                return@eval
            }
            val raw = unwrapJs(value)
            Log.i(TAG, "apply result requestId=$requestId raw=${raw.take(160)}")
            if (raw != "started") {
                applying = false
                if (applyAttempts < APPLY_LIMIT) {
                    applyAttempts += 1
                    mainHandler.postDelayed({ applyPending(requestId) }, APPLY_DELAY_MS)
                } else {
                    finishTimeout(requestId, "SHELL_NOT_READY")
                }
                return@eval
            }
            notifyReady()
            pollCount = 0
            pollCompletion(requestId)
        }
    }

    private fun pollCompletion(requestId: Long) {
        if (disposed) return
        if (!presentAck.isActive(requestId)) {
            applying = false
            return
        }
        eval("(function(){ var a = window.__turnaLastRender; return a ? JSON.stringify(a) : ''; })()") { value ->
            if (!presentAck.isActive(requestId)) {
                applying = false
                return@eval
            }
            val raw = unwrapJs(value)
            if (raw.startsWith("{") && raw.contains("\"type\"")) {
                val type = jsonType(raw)
                // cardAccepted / frameReady are mid-present. Completing here
                // used to fire RENDER_TIMEOUT before renderComplete arrived.
                if (type == "cardAccepted" || type == "frameReady") {
                    if (pollCount < POLL_LIMIT) {
                        pollCount += 1
                        mainHandler.postDelayed({ pollCompletion(requestId) }, APPLY_DELAY_MS)
                        return@eval
                    }
                } else if (type == "renderComplete" || type == "renderError") {
                    Log.i(TAG, "poll complete requestId=$requestId raw=${raw.take(160)}")
                    applying = false
                    completeFromJs(requestId, raw)
                    return@eval
                }
            }
            if (pollCount < POLL_LIMIT) {
                pollCount += 1
                if (pollCount == 1 || pollCount % 20 == 0) {
                    Log.i(TAG, "poll wait requestId=$requestId n=$pollCount")
                }
                mainHandler.postDelayed({ pollCompletion(requestId) }, APPLY_DELAY_MS)
            } else {
                applying = false
                finishTimeout(requestId, "RENDER_TIMEOUT")
            }
        }
    }

    private fun jsonType(raw: String): String {
        val key = "\"type\""
        val start = raw.indexOf(key)
        if (start < 0) return ""
        val colon = raw.indexOf(':', start + key.length)
        if (colon < 0) return ""
        val firstQuote = raw.indexOf('"', colon + 1)
        if (firstQuote < 0) return ""
        val secondQuote = raw.indexOf('"', firstQuote + 1)
        if (secondQuote < 0) return ""
        return raw.substring(firstQuote + 1, secondQuote)
    }

    private fun unwrapJs(value: String?): String {
        if (value == null || value == "null") return ""
        var raw = value.trim()
        if (raw.length >= 2 && raw.startsWith("\"") && raw.endsWith("\"")) {
            raw = raw.substring(1, raw.length - 1)
                .replace("\\\\", "\\")
                .replace("\\\"", "\"")
                .replace("\\n", "\n")
        }
        return raw
    }

    private fun completeFromJs(requestId: Long, raw: String) {
        try {
            val parsed = JSONObject(raw)
            val height = parsed.optDouble("height", 0.0)
            val generation = parsed.optLong("generation")
            if (height > 0 && presentAck.shouldPublishHeight(generation, height)) {
                channel.invokeMethod("pageHeightChanged", height)
            }
            val code = parsed.optString("stableCode").ifEmpty { parsed.optString("code") }
            val type = parsed.optString("type")
            val ok = type == "renderComplete"
            if (!ok) {
                channel.invokeMethod("renderError", code.ifEmpty { "RENDER_TIMEOUT" })
            }
            finishPresent(
                requestId,
                PresentAckCoordinator.PresentResult(
                    ok = ok,
                    code = code.ifEmpty { if (ok) null else "RENDER_TIMEOUT" },
                    generation = if (parsed.has("generation")) generation else null,
                    side = parsed.optString("side").ifEmpty { pendingSide },
                    height = height,
                    recoverable = !ok,
                ),
            )
        } catch (error: Exception) {
            Log.e(TAG, "present parse failed raw=$raw", error)
            finishTimeout(requestId, "RENDER_TIMEOUT")
        }
    }

    private fun finishTimeout(requestId: Long, code: String) {
        applying = false
        if (!presentAck.isActive(requestId)) return
        Log.w(TAG, "present timeout requestId=$requestId code=$code")
        channel.invokeMethod("renderError", code)
        finishPresent(
            requestId,
            PresentAckCoordinator.PresentResult(
                ok = false,
                code = code,
                recoverable = true,
            ),
        )
    }

    private fun finishPresent(
        requestId: Long,
        result: PresentAckCoordinator.PresentResult,
    ) {
        val completed = presentAck.complete(requestId, result) ?: return
        succeed(completed.toMap())
    }

    private fun succeed(payload: Map<String, Any?>) {
        val pending = waitingResult ?: return
        waitingResult = null
        pending.success(payload)
    }

    private fun eval(script: String, callback: ((String?) -> Unit)? = null) {
        if (disposed) return
        webView.evaluateJavascript(script) { value ->
            callback?.invoke(value)
        }
    }

    companion object {
        private const val TAG = "OfficialAnkiReviewer"
        private const val APPLY_LIMIT = 200
        private const val POLL_LIMIT = 400
        private const val APPLY_DELAY_MS = 50L
        private const val PRESENT_DEADLINE_MS = 20_000L
        private val NIGHT_BACKGROUND = Color.parseColor("#111111")
    }
}
