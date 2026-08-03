// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/ai/engine/ai_engine_config.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/service/locator.dart';

/// Owns the single [AiEngineConfig] the engine reads.
///
/// `@lazySingleton` so constructor-injected collaborators (the engine, the
/// providers) resolve the same instance the UI watches via
/// `ChangeNotifierProvider<AiEngineConfigHolder>` in `providers.dart`.
///
/// Persistence: the config (including the API key) is serialized to
/// SharedPreferences via [LocalStateKeys.aiEngineConfig] so it survives an app
/// restart. [loadPersisted] is called once during startup; [updateConfig]
/// re-persists on every write. The API key is therefore stored in plain text
/// on the device - the user explicitly opted into this for convenience. Writes
/// go through the raw `StreamingSharedPreferences` to bypass
/// `AppPrefs.printBefore`, so the key is never emitted to logs (even under the
/// `veryVerbose` debug switch). When [AppPrefs] is not registered (e.g. in
/// unit tests) the holder silently degrades to in-memory-only behavior.
@lazySingleton
class AiEngineConfigHolder extends ChangeNotifier {
  AiEngineConfigHolder() : _config = const AiEngineConfig(apiKey: '');

  AiEngineConfig _config;

  /// Current engine config. The engine reads this at call time; the Settings
  /// sheet writes via [updateConfig].
  AiEngineConfig get config => _config;

  /// Replace the config, persist it, and notify listeners. Callers should
  /// build the next config with [AiEngineConfig.copyWith] (or construct fresh)
  /// and pass it in.
  void updateConfig(AiEngineConfig next) {
    _config = next;
    _persist();
    notifyListeners();
  }

  /// Hydrate the config from SharedPreferences. Call once during app startup
  /// (after [setupLocator]); no-op when nothing is stored, the JSON is
  /// corrupt, or [AppPrefs] is not registered (tests). Notifies listeners when
  /// a stored config is loaded.
  Future<void> loadPersisted() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final raw = prefs.preferences
          .getString(LocalStateKeys.aiEngineConfig, defaultValue: '')
          .getValue();
      if (raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _config = AiEngineConfig.fromJson(decoded);
        notifyListeners();
      }
    } catch (_) {
      // Corrupt / partial JSON - keep the in-memory default rather than crash.
    }
  }

  /// Resolve [AppPrefs] if it is registered, else `null`. Guarded so the
  /// holder works in test contexts that skip [setupLocator].
  AppPrefs? get _prefs {
    if (!getIt.isRegistered<AppPrefs>()) return null;
    try {
      return getIt<AppPrefs>();
    } catch (_) {
      return null;
    }
  }

  void _persist() {
    final prefs = _prefs;
    if (prefs == null) return;
    final raw = jsonEncode(_config.toJson());
    // Fire-and-forget; StreamingSharedPreferences.setString is async. Writing
    // on `prefs.preferences` (not `AppPrefs.setString`) skips printBefore so
    // the API key is not logged.
    prefs.preferences.setString(LocalStateKeys.aiEngineConfig, raw);
  }
}
