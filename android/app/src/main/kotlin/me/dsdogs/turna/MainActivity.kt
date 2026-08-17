package me.dsdogs.turna

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import me.dsdogs.turna.anki.reviewer.OfficialAnkiReviewerPlugin

class MainActivity : FlutterActivity() {
    private val ttsSettingsChannel = "turna/tts_settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        OfficialAnkiReviewerPlugin.register(this, flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ttsSettingsChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openTtsSettings" -> {
                    try {
                        // Public action for Text-to-speech output settings.
                        val intent = Intent("com.android.settings.TTS_SETTINGS")
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            // Fallback: general settings if OEM removed TTS_SETTINGS.
                            val fallback = Intent(Settings.ACTION_SETTINGS)
                            fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(fallback)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error(
                                "TTS_SETTINGS_UNAVAILABLE",
                                e2.message,
                                null,
                            )
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
