// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/service/locator.dart';

/// App-wide user settings that need to persist across launches.
///
/// Uses [AppPrefs] / StreamingSharedPreferences under the hood and exposes
/// a [ChangeNotifier] API so the UI can react instantly.
@lazySingleton
class SettingsProvider extends ChangeNotifier {
  final AppPrefs _appPrefs;

  bool _soundEffectsEnabled = true;
  bool _hapticFeedbackEnabled = true;
  double _ttsSpeed = 1.0;
  TtsEngine _ttsEngine = TtsEngine.system;

  SettingsProvider(this._appPrefs) {
    _load();
  }

  bool get soundEffectsEnabled => _soundEffectsEnabled;
  bool get hapticFeedbackEnabled => _hapticFeedbackEnabled;
  double get ttsSpeed => _ttsSpeed;
  TtsEngine get ttsEngine => _ttsEngine;

  void _load() {
    _soundEffectsEnabled = _appPrefs.preferences
        .getBool(LocalStateKeys.soundEffects, defaultValue: true)
        .getValue();
    _hapticFeedbackEnabled = _appPrefs.preferences
        .getBool(LocalStateKeys.haptic, defaultValue: true)
        .getValue();
    _ttsSpeed = _appPrefs.preferences
        .getDouble(LocalStateKeys.ttsSpeed, defaultValue: 1.0)
        .getValue();
    _ttsEngine = _parseTtsEngine(
      _appPrefs.preferences
          .getString(LocalStateKeys.ttsEngine, defaultValue: TtsEngine.system.name)
          .getValue(),
    );
  }

  static TtsEngine _parseTtsEngine(String value) {
    return TtsEngine.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TtsEngine.system,
    );
  }

  Future<void> setSoundEffects(bool value) async {
    _soundEffectsEnabled = value;
    await _appPrefs.setBool(LocalStateKeys.soundEffects, value: value);
    notifyListeners();
  }

  Future<void> setHapticFeedback(bool value) async {
    _hapticFeedbackEnabled = value;
    await _appPrefs.setBool(LocalStateKeys.haptic, value: value);
    notifyListeners();
  }

  Future<void> setTtsSpeed(double value) async {
    final clamped = value.clamp(0.5, 2.0);
    _ttsSpeed = clamped;
    await _appPrefs.setDouble(LocalStateKeys.ttsSpeed, clamped);
    notifyListeners();
  }

  Future<void> setTtsEngine(TtsEngine value) async {
    _ttsEngine = value;
    await _appPrefs.setString(LocalStateKeys.ttsEngine, value.name);
    notifyListeners();
  }

  /// Lightweight helper so other controllers don't have to import
  /// [HapticFeedback] directly or repeat the enabled-check.
  void triggerHaptic(HapticFeedbackType type) {
    if (!_hapticFeedbackEnabled) return;
    switch (type) {
      case HapticFeedbackType.light:
        HapticFeedback.lightImpact();
      case HapticFeedbackType.medium:
        HapticFeedback.mediumImpact();
      case HapticFeedbackType.heavy:
        HapticFeedback.heavyImpact();
    }
  }
}

enum HapticFeedbackType { light, medium, heavy }

/// Available TTS sources.
///
/// - [system]: use the device's built-in TTS engine (Google TTS on Android,
///   Apple system TTS on iOS).
/// - [offline]: use the bundled Piper Swahili model.
enum TtsEngine { system, offline }
