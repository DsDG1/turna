package me.dsdogs.turna.anki.reviewer

import android.app.Activity
import android.os.Bundle
import android.webkit.WebView
import android.widget.FrameLayout
import java.io.File

class OfficialAnkiReviewerHarnessActivity : Activity() {
    lateinit var webView: WebView
    lateinit var mediaRoot: File

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        mediaRoot = File(cacheDir, "official-anki-media").apply { mkdirs() }
        webView = WebView(this)
        OfficialAnkiWebPolicy.apply(webView, true)
        val handler = OfficialAnkiMediaHandler(mediaRoot) { name ->
            OfficialAnkiReviewerPlugin.loadReviewerAsset(this, name)
        }
        webView.webViewClient = OfficialAnkiReviewerClient(
            handler,
            onReady = {},
            onError = {},
        )
        setContentView(
            FrameLayout(this).apply {
                addView(
                    webView,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                    ),
                )
            },
        )
        webView.loadUrl(OfficialAnkiWebPolicy.SHELL_URL)
        webView.post {
            webView.evaluateJavascript(TEST_PROBE, null)
        }
    }

    companion object {
        // Test-only parent helper. Production Reviewer never ships this API.
        private const val TEST_PROBE = """
            (function () {
              if (window.OfficialReviewerTest) return;
              window.OfficialReviewerTest = {
                snapshot: function (generation, nonce) {
                  window.__turnaLastSnapshot = null;
                  var frame = document.getElementById('card-frame');
                  if (!frame || !frame.contentWindow) return '0';
                  frame.contentWindow.postMessage(
                    {v:1, type:'testSnapshot', generation:generation, nonce:nonce},
                    '*'
                  );
                  return '1';
                }
              };
              window.addEventListener('message', function (event) {
                var data = event.data || {};
                if (data && data.type === 'testSnapshotResult') {
                  window.__turnaLastSnapshot = data;
                }
              });
            })();
        """
    }

    override fun onDestroy() {
        webView.destroy()
        super.onDestroy()
    }
}
