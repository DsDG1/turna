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
  bool _dailyReminderEnabled = false;
  int _dailyReminderHour = 19;
  int _dailyReminderMinute = 0;

  SettingsProvider(this._appPrefs) {
    _load();
  }

  bool get soundEffectsEnabled => _soundEffectsEnabled;
  bool get hapticFeedbackEnabled => _hapticFeedbackEnabled;
  double get ttsSpeed => _ttsSpeed;
  bool get dailyReminderEnabled => _dailyReminderEnabled;
  int get dailyReminderHour => _dailyReminderHour;
  int get dailyReminderMinute => _dailyReminderMinute;

  TimeOfDay get dailyReminderTime =>
      TimeOfDay(hour: _dailyReminderHour, minute: _dailyReminderMinute);

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
    _dailyReminderEnabled = _appPrefs.preferences
        .getBool(LocalStateKeys.dailyReminderEnabled, defaultValue: false)
        .getValue();
    _dailyReminderHour = _appPrefs.preferences
        .getInt(LocalStateKeys.dailyReminderHour, defaultValue: 19)
        .getValue();
    _dailyReminderMinute = _appPrefs.preferences
        .getInt(LocalStateKeys.dailyReminderMinute, defaultValue: 0)
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

  Future<void> setDailyReminderEnabled(bool value) async {
    _dailyReminderEnabled = value;
    await _appPrefs.setBool(LocalStateKeys.dailyReminderEnabled, value: value);
    notifyListeners();
  }

  Future<void> setDailyReminderTime(TimeOfDay time) async {
    _dailyReminderHour = time.hour;
    _dailyReminderMinute = time.minute;
    await _appPrefs.setInt(LocalStateKeys.dailyReminderHour, time.hour);
    await _appPrefs.setInt(LocalStateKeys.dailyReminderMinute, time.minute);
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
