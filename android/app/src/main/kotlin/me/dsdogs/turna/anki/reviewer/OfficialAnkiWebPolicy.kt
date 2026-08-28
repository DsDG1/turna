package me.dsdogs.turna.anki.reviewer

import android.annotation.SuppressLint
import android.os.Build
import android.webkit.WebSettings
import android.webkit.WebView

object OfficialAnkiWebPolicy {
    const val ORIGIN_HOST = OfficialAnkiCsp.ORIGIN_HOST
    const val SHELL_URL = OfficialAnkiCsp.SHELL_URL
    const val CSP = OfficialAnkiCsp.VALUE

    @SuppressLint("SetJavaScriptEnabled")
    fun apply(webView: WebView, diagnostics: Boolean, textZoom: Int = 100) {
        val settings = webView.settings
        settings.javaScriptEnabled = true
        // Text-only zoom for the card content (100 = author CSS as-is).
        // Setting it explicitly also replaces the system font-scale the
        // WebView would otherwise inherit, mirroring how the Flutter root
        // overrides MediaQuery.textScaler with the in-app setting.
        settings.textZoom = textZoom.coerceIn(100, 200)
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        settings.allowFileAccessFromFileURLs = false
        settings.allowUniversalAccessFromFileURLs = false
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        settings.setGeolocationEnabled(false)
        settings.mediaPlaybackRequiresUserGesture = false
        settings.javaScriptCanOpenWindowsAutomatically = false
        settings.setSupportMultipleWindows(false)
        settings.domStorageEnabled = false
        settings.databaseEnabled = false
        settings.blockNetworkImage = false
        // Interceptor is the network firewall. Blocking loads here also
        // prevents https://anki.local from reaching shouldInterceptRequest.
        // Chromium throws SecurityException if INTERNET is missing.
        settings.blockNetworkLoads = false
        settings.cacheMode = WebSettings.LOAD_NO_CACHE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            settings.safeBrowsingEnabled = true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            android.webkit.CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false)
        }
        webView.setDownloadListener { _, _, _, _, _ -> }
        // Never enable debugging from debug builds alone.
        WebView.setWebContentsDebuggingEnabled(diagnostics)
    }

    fun isShellUrl(url: String?): Boolean {
        if (url == null) return false
        return url == SHELL_URL || url.startsWith("$SHELL_URL?")
    }
}
