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
    private var pendingPayload: JSONObject? = null
    private var pendingSide: String = "question"
    private var applyAttempts = 0
    private var waitingResult: MethodChannel.Result? = null
    private var pollCount = 0
    private val presentAck = PresentAckCoordinator()

    init {
        channel.setMethodCallHandler(this)
        webView.setBackgroundColor(Color.WHITE)
        webView.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        OfficialAnkiWebPolicy.apply(webView, diagnostics)
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
        if (pendingPayload != null && waitingResult != null && active != null) {
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
            pending?.success(superseded.toMap())
        }
        waitingResult = result
        pollCount = 0
        applyAttempts = 0
        applyPending(request.id)
    }

    private fun applyPending(requestId: Long) {
        if (disposed) return
        if (!presentAck.isActive(requestId)) return
        val payload = pendingPayload
        if (payload == null) {
            eval("(function(){ return window.OfficialReviewer ? 'ready' : 'not_ready'; })()") { value ->
                if (!presentAck.isActive(requestId)) return@eval
                if ((value?.trim('"') ?: "") == "not_ready" && applyAttempts < 40) {
                    applyAttempts += 1
                    mainHandler.postDelayed({ applyPending(requestId) }, 50)
                } else {
                    notifyReady()
                    finishPresent(
                        requestId,
                        PresentAckCoordinator.PresentResult(ok = true, side = "ready"),
                    )
                }
            }
            return
        }
        val side = JSONObject.quote(pendingSide)
        val script =
            "(function(){ if (!window.OfficialReviewer) return 'not_ready'; " +
                "window.__turnaLastRender = null; " +
                "OfficialReviewer.present($payload, $side); return 'started'; })()"
        eval(script) { value ->
            if (!presentAck.isActive(requestId)) return@eval
            val raw = value?.trim('"') ?: ""
            if (raw == "not_ready" && applyAttempts < 40) {
                applyAttempts += 1
                mainHandler.postDelayed({ applyPending(requestId) }, 50)
                return@eval
            }
            notifyReady()
            pollCompletion(requestId)
        }
    }

    private fun pollCompletion(requestId: Long) {
        if (disposed) return
        if (!presentAck.isActive(requestId)) return
        eval("(function(){ var a = window.__turnaLastRender; return a ? JSON.stringify(a) : ''; })()") { value ->
            if (!presentAck.isActive(requestId)) return@eval
            val raw = value?.trim() ?: ""
            val json = raw.trim('"').replace("\\\"", "\"")
            if (json.isNotEmpty() && json != "null" && json != "undefined") {
                try {
                    val parsed = JSONObject(if (json.startsWith("{")) json else raw.trim('"'))
                    val height = parsed.optDouble("height", 0.0)
                    val generation = parsed.optLong("generation")
                    if (height > 0 && presentAck.shouldPublishHeight(generation, height)) {
                        channel.invokeMethod("pageHeightChanged", height)
                    }
                    val code = parsed.optString("stableCode")
                    if (parsed.optString("type") == "renderError" ||
                        code == "MATHJAX_ASSET_MISSING" ||
                        code == "RENDER_TIMEOUT" ||
                        code == PresentAckCoordinator.CODE_SUPERSEDED
                    ) {
                        channel.invokeMethod("renderError", code.ifEmpty { parsed.toString() })
                    }
                    finishPresent(
                        requestId,
                        PresentAckCoordinator.PresentResult(
                            ok = parsed.optString("type") == "renderComplete",
                            code = code.ifEmpty { null },
                            generation = if (parsed.has("generation")) generation else null,
                            side = parsed.optString("side"),
                            height = height,
                            recoverable = code == "RENDER_TIMEOUT" ||
                                code == PresentAckCoordinator.CODE_SUPERSEDED ||
                                code == "MATHJAX_ASSET_MISSING" ||
                                code == "MATHJAX_TYPESET_FAILED",
                        ),
                    )
                    return@eval
                } catch (_: Exception) {
                }
            }
            if (pollCount < 40) {
                pollCount += 1
                mainHandler.postDelayed({ pollCompletion(requestId) }, 50)
            } else {
                channel.invokeMethod("renderError", "RENDER_TIMEOUT")
                finishPresent(
                    requestId,
                    PresentAckCoordinator.PresentResult(
                        ok = false,
                        code = "RENDER_TIMEOUT",
                        recoverable = true,
                    ),
                )
            }
        }
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
    }
}
