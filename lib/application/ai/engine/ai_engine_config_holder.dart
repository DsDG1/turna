// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/ai/engine/ai_engine_config.dart';

/// Owns the single in-memory [AiEngineConfig] the engine reads.
///
/// `@lazySingleton` so constructor-injected collaborators (the engine, the
/// providers) resolve the same instance the UI watches via
/// `ChangeNotifierProvider<AiEngineConfigHolder>` in `providers.dart`.
///
/// Security stance (unchanged from the legacy `AiApiConfig`): the API key is
/// held in memory only and is **never persisted** to prefs / shared prefs /
/// disk. A full app restart resets the config to the DeepSeek default with an
/// empty key.
@lazySingleton
class AiEngineConfigHolder extends ChangeNotifier {
  AiEngineConfigHolder() : _config = const AiEngineConfig(apiKey: '');

  AiEngineConfig _config;

  /// Current engine config. The engine reads this at call time; the Settings
  /// sheet writes via [updateConfig].
  AiEngineConfig get config => _config;

  /// Replace the config and notify listeners. Callers should build the next
  /// config with [AiEngineConfig.copyWith] (or construct fresh) and pass it in.
  void updateConfig(AiEngineConfig next) {
    _config = next;
    notifyListeners();
  }
}
