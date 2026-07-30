// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:injectable/injectable.dart';

/// Bridges the HarmonyOS system AI assistant ("小艺") to Flutter.
///
/// On HarmonyOS the native `XiaoyiPlugin` registers a MethodChannel named
/// `com.varnamala/xiaoyi` that exposes:
///   - `isSupported()` → `true` (only present on HarmonyOS)
///   - `askXiaoyi({prompt})` → hands the prompt to 小艺 via `startAbility`
///
/// On Android / iOS / Web the channel does not exist, so [isSupported]
/// returns `false` and callers fall back to the existing DeepSeek AI hint
/// flow — keeping Android behavior unchanged.
@lazySingleton
class XiaoyiService {
  static const MethodChannel _channel = MethodChannel('com.varnamala/xiaoyi');

  bool? _supportedCache;

  /// `true` only when the HarmonyOS native plugin is registered. Safe to call
  /// on any platform: a missing channel yields `false` rather than throwing.
  Future<bool> get isSupported async {
    if (kIsWeb) return false;
    if (_supportedCache != null) return _supportedCache!;
    try {
      final res = await _channel.invokeMethod<bool>('isSupported');
      _supportedCache = res ?? false;
    } on PlatformException catch (_) {
      _supportedCache = false;
    } on MissingPluginException catch (_) {
      _supportedCache = false;
    }
    return _supportedCache!;
  }

  /// Hand [prompt] to 小艺 on HarmonyOS. Throws a [PlatformException] when the
  /// launch fails (e.g. 小艺 not available); the caller is expected to catch
  /// and surface a user-facing message. No-op (throws) on non-HarmonyOS.
  Future<void> ask(String prompt) async {
    if (kIsWeb) {
      throw PlatformException(code: 'UNSUPPORTED', message: '小艺仅在鸿蒙端可用');
    }
    try {
      await _channel.invokeMethod<void>('askXiaoyi', <String, Object?>{
        'prompt': prompt,
      });
    } on MissingPluginException catch (e) {
      throw PlatformException(code: 'UNSUPPORTED', message: e.message);
    }
  }
}