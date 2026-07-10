// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Project imports:
import 'package:words625/service/locator.dart';

/// App-wide user settings that need to persist across launches.
///
/// Uses [AppPrefs] / StreamingSharedPreferences under the hood and exposes
/// a [ChangeNotifier] API so the UI can react instantly.
class SettingsProvider extends ChangeNotifier {
  final AppPrefs _appPrefs;

  bool _soundEffectsEnabled = true;
  bool _hapticFeedbackEnabled = true;
  double _ttsSpeed = 1.0;

  SettingsProvider(this._appPrefs) {
    _load();
  }

  bool get soundEffectsEnabled => _soundEffectsEnabled;
  bool get hapticFeedbackEnabled => _hapticFeedbackEnabled;
  double get ttsSpeed => _ttsSpeed;

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
