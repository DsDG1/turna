# Varnamala ProGuard / R8 rules
#
# Keeps for code that R8 cannot see statically — FFI/JNI bindings, reflection-
# based serialization, and generated data classes. Without these, minifyEnabled
# strips the entry points and the app crashes at runtime.

# ── sherpa_onnx (ONNX Runtime + Piper TTS) ──────────────────────────────────
# JNI bridge classes invoked from native code; must keep class + native methods.
-keep class com.k2fsa.sherpa.onnx.** { *; }
-keepclassmembers class com.k2fsa.sherpa.onnx.** {
    public *;
    native <methods>;
}

# ── flutter_tts ─────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.tts.** { *; }

# ── audioplayers ────────────────────────────────────────────────────────────
-keep class xyz.luan.audioplayers.** { *; }

# ── drift / sqlite3 (reflection-based DB serialization) ─────────────────────
-keep class * extends androidx.sqlite.db.SupportSQLiteOpenHelper { *; }
-keep class drift.** { *; }
-keepclassmembers class * extends com.jiuli.drift.runtime.** { *; }
# Keep app-generated drift companion classes (reflected by drift runtime).
-keep class **.Database { *; }
-keep class **$Companion { *; }
-keep class **$TableInfo { *; }
# sqlite3_flutter_libs native entry.
-keep class com.sqlite3_flutter_libs.** { *; }

# ── Freezed / json_serializable generated classes ───────────────────────────
# Generated fromJson/toJson are plain Dart methods called directly (no
# reflection), so R8 sees them statically. Keep annotations + generic
# signatures intact for code that introspects them.
-keepattributes Signature, *Annotation*

# ── path_provider / url_launcher / share_plus / package_info_plus ────────────
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class io.flutter.plugins.share.** { *; }
-keep class dev.fluttercommunity.plus.package_info.** { *; }

# ── streaming_shared_preferences ────────────────────────────────────────────
-keep class com.jrdbnntt.** { *; }