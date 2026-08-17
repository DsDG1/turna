package me.dsdogs.turna.anki.reviewer

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine

object OfficialAnkiReviewerPlugin {
    const val VIEW_TYPE = "official_anki_reviewer"
    private const val TAG = "OfficialAnkiReviewer"

    fun register(context: Context, flutterEngine: FlutterEngine) {
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                VIEW_TYPE,
                OfficialAnkiReviewerFactory(
                    flutterEngine.dartExecutor.binaryMessenger,
                ) { name -> loadReviewerAsset(context, name) },
            )
    }

    fun loadReviewerAsset(context: Context, name: String): ByteArray? {
        val candidates = listOf(
            "flutter_assets/assets/anki_reviewer/$name",
            "assets/flutter_assets/assets/anki_reviewer/$name",
            "assets/anki_reviewer/$name",
        )
        for (path in candidates) {
            try {
                return context.assets.open(path).use { it.readBytes() }
            } catch (_: Exception) {
            }
        }
        Log.e(TAG, "missing reviewer asset $name")
        if (name.contains("mathjax") || name.endsWith("tex-svg-full.js")) {
            Log.e(TAG, "MATHJAX_ASSET_MISSING")
        }
        return null
    }
}
