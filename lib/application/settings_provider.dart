// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/di/injection.dart';
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
  bool _useXiaoyiHint = false;
  double _srsDesiredRetention = 0.9;
  bool _hasCustomFsrsWeights = false;
  String _fsrsOptimizedAt = '';
  int _fsrsOptimizedReviews = 0;

  SettingsProvider(this._appPrefs) {
    _load();
  }

  bool get soundEffectsEnabled => _soundEffectsEnabled;
  bool get hapticFeedbackEnabled => _hapticFeedbackEnabled;
  double get ttsSpeed => _ttsSpeed;
  bool get dailyReminderEnabled => _dailyReminderEnabled;
  int get dailyReminderHour => _dailyReminderHour;
  int get dailyReminderMinute => _dailyReminderMinute;
  bool get useXiaoyiHint => _useXiaoyiHint;
  /// FSRS target retention (0.80–0.95). Binary scoring only — not a grade UI.
  double get srsDesiredRetention => _srsDesiredRetention;
  bool get hasCustomFsrsWeights => _hasCustomFsrsWeights;
  String get fsrsOptimizedAt => _fsrsOptimizedAt;
  int get fsrsOptimizedReviews => _fsrsOptimizedReviews;

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
    _useXiaoyiHint = _appPrefs.preferences
        .getBool(LocalStateKeys.useXiaoyiHint, defaultValue: false)
        .getValue();
    _srsDesiredRetention = _appPrefs.preferences
        .getDouble(LocalStateKeys.srsDesiredRetention, defaultValue: 0.9)
        .getValue()
        .clamp(0.8, 0.95);
    _hasCustomFsrsWeights = _appPrefs.preferences
        .getString(LocalStateKeys.srsFsrsParameters, defaultValue: '')
        .getValue()
        .isNotEmpty;
    _fsrsOptimizedAt = _appPrefs.preferences
        .getString(LocalStateKeys.srsFsrsOptimizedAt, defaultValue: '')
        .getValue();
    _fsrsOptimizedReviews = _appPrefs.preferences
        .getInt(LocalStateKeys.srsFsrsOptimizedReviews, defaultValue: 0)
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

  Future<void> setUseXiaoyiHint(bool value) async {
    _useXiaoyiHint = value;
    await _appPrefs.setBool(LocalStateKeys.useXiaoyiHint, value: value);
    notifyListeners();
  }

  Future<void> setSrsDesiredRetention(double value) async {
    final clamped = value.clamp(0.8, 0.95);
    _srsDesiredRetention = clamped;
    await _appPrefs.setDouble(LocalStateKeys.srsDesiredRetention, clamped);
    // Hot-reload FSRS engines without restarting the app.
    try {
      getIt<SrsProvider>().setDesiredRetention(clamped);
      getIt<GrammarReviewProvider>().setDesiredRetention(clamped);
    } catch (_) {
      // DI not ready in some tests — prefs still updated.
    }
    notifyListeners();
  }

  /// Persist optimized FSRS weights and refresh schedulers.
  Future<void> applyFsrsParameters(
    List<double> parameters, {
    required int reviewCount,
  }) async {
    try {
      await getIt<SrsProvider>().setFsrsParameters(parameters);
      await getIt<GrammarReviewProvider>().setFsrsParameters(parameters);
    } catch (_) {}
    final now = DateTime.now().toIso8601String();
    await _appPrefs.setString(LocalStateKeys.srsFsrsOptimizedAt, now);
    await _appPrefs.setInt(LocalStateKeys.srsFsrsOptimizedReviews, reviewCount);
    _hasCustomFsrsWeights = true;
    _fsrsOptimizedAt = now;
    _fsrsOptimizedReviews = reviewCount;
    notifyListeners();
  }

  Future<void> clearFsrsParameters() async {
    try {
      await getIt<SrsProvider>().setFsrsParameters(null);
      await getIt<GrammarReviewProvider>().setFsrsParameters(null);
    } catch (_) {}
    await _appPrefs.setString(LocalStateKeys.srsFsrsParameters, '');
    await _appPrefs.setString(LocalStateKeys.srsFsrsOptimizedAt, '');
    await _appPrefs.setInt(LocalStateKeys.srsFsrsOptimizedReviews, 0);
    _hasCustomFsrsWeights = false;
    _fsrsOptimizedAt = '';
    _fsrsOptimizedReviews = 0;
    notifyListeners();
  }

  /// Restore learning-related prefs to their factory defaults.
  ///
  /// Does **not** change target language, theme, accessibility, sound/haptics,
  /// or lesson progress — only TTS speed, daily reminder, Xiaoyi hint, and
  /// SRS desired retention.
  Future<void> resetLearningDefaults() async {
    _ttsSpeed = 1.0;
    _dailyReminderEnabled = false;
    _dailyReminderHour = 19;
    _dailyReminderMinute = 0;
    _useXiaoyiHint = false;
    _srsDesiredRetention = 0.9;
    await _appPrefs.setDouble(LocalStateKeys.ttsSpeed, 1.0);
    await _appPrefs.setBool(LocalStateKeys.dailyReminderEnabled, value: false);
    await _appPrefs.setInt(LocalStateKeys.dailyReminderHour, 19);
    await _appPrefs.setInt(LocalStateKeys.dailyReminderMinute, 0);
    await _appPrefs.setBool(LocalStateKeys.useXiaoyiHint, value: false);
    await _appPrefs.setDouble(LocalStateKeys.srsDesiredRetention, 0.9);
    try {
      getIt<SrsProvider>().setDesiredRetention(0.9);
      getIt<GrammarReviewProvider>().setDesiredRetention(0.9);
    } catch (_) {}
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
