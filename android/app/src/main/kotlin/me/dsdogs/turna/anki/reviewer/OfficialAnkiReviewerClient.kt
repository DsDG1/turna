package me.dsdogs.turna.anki.reviewer

import android.net.http.SslError
import android.webkit.ClientCertRequest
import android.webkit.HttpAuthHandler
import android.webkit.SslErrorHandler
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient

class OfficialAnkiReviewerClient(
    private val mediaHandler: OfficialAnkiMediaHandler,
    private val onReady: () -> Unit,
    private val onError: (String) -> Unit,
) : WebViewClient() {
    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
        return !OfficialAnkiWebPolicy.isShellUrl(request.url.toString())
    }

    override fun shouldInterceptRequest(
        view: WebView,
        request: WebResourceRequest,
    ): WebResourceResponse {
        return mediaHandler.intercept(request)
    }

    override fun onPageFinished(view: WebView, url: String) {
        if (OfficialAnkiWebPolicy.isShellUrl(url)) {
            onReady()
        }
    }

    override fun onReceivedError(
        view: WebView,
        request: WebResourceRequest,
        error: android.webkit.WebResourceError,
    ) {
        if (request.isForMainFrame) {
            onError(error.description?.toString() ?: "webview_error")
        }
    }

    override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
        handler.cancel()
        onError("ssl")
    }

    override fun onReceivedHttpAuthRequest(
        view: WebView,
        handler: HttpAuthHandler,
        host: String,
        realm: String,
    ) {
        handler.cancel()
    }

    override fun onReceivedClientCertRequest(view: WebView, request: ClientCertRequest) {
        request.cancel()
    }
}
