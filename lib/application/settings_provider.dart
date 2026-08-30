// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

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
  bool _autoRotateEnabled = false;
  double _srsDesiredRetention = 0.9;
  bool _hasCustomFsrsWeights = false;
  String _fsrsOptimizedAt = '';
  int _fsrsOptimizedReviews = 0;
  bool _ankiForceDisableJs = false;

  SettingsProvider(this._appPrefs) {
    _load();
  }

  bool get soundEffectsEnabled => _soundEffectsEnabled;
  bool get hapticFeedbackEnabled => _hapticFeedbackEnabled;
  double get ttsSpeed => _ttsSpeed;
  bool get dailyReminderEnabled => _dailyReminderEnabled;
  int get dailyReminderHour => _dailyReminderHour;
  int get dailyReminderMinute => _dailyReminderMinute;

  /// Screen auto-rotation. false (default) locks portrait; true follows device.
  bool get autoRotateEnabled => _autoRotateEnabled;

  /// FSRS target retention (0.80–0.95). Binary scoring only — not a grade UI.
  double get srsDesiredRetention => _srsDesiredRetention;
  bool get hasCustomFsrsWeights => _hasCustomFsrsWeights;
  String get fsrsOptimizedAt => _fsrsOptimizedAt;
  int get fsrsOptimizedReviews => _fsrsOptimizedReviews;

  /// Force-disable template JS in the Official Anki WebView. Encrypted
  /// decks then show ciphertext. Lite-threshold (shell-only large decks)
  /// died with the Legacy assembler.
  bool get ankiForceDisableJs => _ankiForceDisableJs;

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
    _autoRotateEnabled = _appPrefs.preferences
        .getBool(LocalStateKeys.autoRotate, defaultValue: false)
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
    _ankiForceDisableJs = _appPrefs.preferences
        .getBool(LocalStateKeys.ankiForceDisableJs, defaultValue: false)
        .getValue();
  }

  /// Re-reads every persisted setting and notifies listeners. Used after a
  /// backup restore so displayed values match the persisted snapshot without
  /// an app restart (PostRestoreReloadRegistry step).
  void reload() {
    _load();
    notifyListeners();
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

  Future<void> setAutoRotateEnabled(bool value) async {
    _autoRotateEnabled = value;
    await _appPrefs.setBool(LocalStateKeys.autoRotate, value: value);
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────
  // Per-course smart-TTS settings (keyed by course scope).
  // ──────────────────────────────────────────────────────────────

  /// Whether tapping an option / revealing a card auto-reads it aloud, for
  /// the course identified by [scope] ('' = built-in, 'anki:importId' =
  /// imported deck). Defaults to true (auto-read on).
  bool autoReadOnTapFor(String scope) {
    return _appPrefs.preferences
        .getBool(LocalStateKeys.autoReadOnTapKey(scope), defaultValue: true)
        .getValue();
  }

  Future<void> setAutoReadOnTapFor(String scope, bool value) async {
    await _appPrefs.setBool(LocalStateKeys.autoReadOnTapKey(scope),
        value: value);
    notifyListeners();
  }

  /// BCP-47 base code of the "translation / native" language for the course
  /// identified by [scope]. Used as the TTS fallback voice for plain-Latin
  /// text that is neither the target language nor a detectable non-Latin
  /// script. Defaults to 'en'.
  String nativeLanguageCodeFor(String scope) {
    return _appPrefs.preferences
        .getString(LocalStateKeys.nativeLanguageKey(scope), defaultValue: 'en')
        .getValue();
  }

  Future<void> setNativeLanguageCodeFor(String scope, String value) async {
    await _appPrefs.setString(LocalStateKeys.nativeLanguageKey(scope), value);
    notifyListeners();
  }

  Future<void> setAnkiForceDisableJs(bool value) async {
    _ankiForceDisableJs = value;
    await _appPrefs.setBool(LocalStateKeys.ankiForceDisableJs, value: value);
    notifyListeners();
  }

  Future<void> setSrsDesiredRetention(double value) async {
    final clamped = value.clamp(0.8, 0.95);
    _srsDesiredRetention = clamped;
    await _appPrefs.setDouble(LocalStateKeys.srsDesiredRetention, clamped);
    // Hot-reload FSRS engines without restarting the app. Guarded by
    // isRegistered instead of a swallow-all catch: a scheduling consumer
    // that IS registered but fails must surface, not silently drift.
    if (getIt.isRegistered<SrsProvider>()) {
      getIt<SrsProvider>().setDesiredRetention(clamped);
    }
    if (getIt.isRegistered<GrammarReviewProvider>()) {
      getIt<GrammarReviewProvider>().setDesiredRetention(clamped);
    }
    notifyListeners();
  }

  /// Persist optimized FSRS weights and refresh schedulers.
  ///
  /// DEPRECATED orchestration shim: the transactional implementation lives
  /// in [ApplyFsrsParametersCommand] (both consumers must succeed before
  /// the optimized metadata is written). This shim remains for callers that
  /// only need the display state refreshed and is scheduled for removal
  /// once all call sites use the command.
  Future<void> applyFsrsParameters(
    List<double> parameters, {
    required int reviewCount,
  }) async {
    try {
      await getIt<SrsProvider>().setFsrsParameters(parameters);
      await getIt<GrammarReviewProvider>().setFsrsParameters(parameters);
    } on Object catch (error) {
      throw StateError('FSRS consumers failed to apply parameters: $error');
    }
    final now = DateTime.now().toIso8601String();
    await _appPrefs.setString(LocalStateKeys.srsFsrsOptimizedAt, now);
    await _appPrefs.setInt(LocalStateKeys.srsFsrsOptimizedReviews, reviewCount);
    _hasCustomFsrsWeights = true;
    _fsrsOptimizedAt = now;
    _fsrsOptimizedReviews = reviewCount;
    notifyListeners();
  }

  /// Clear custom FSRS weights. Same transactional note as
  /// [applyFsrsParameters] — prefer [ApplyFsrsParametersCommand].
  Future<void> clearFsrsParameters() async {
    try {
      await getIt<SrsProvider>().setFsrsParameters(null);
      await getIt<GrammarReviewProvider>().setFsrsParameters(null);
    } on Object catch (error) {
      throw StateError('FSRS consumers failed to clear parameters: $error');
    }
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
  /// or lesson progress — only TTS speed, daily reminder, and SRS desired
  /// retention. Orchestration (audio, reminder schedule, Anki limits) lives
  /// in [ResetLearningSettingsCommand] — the provider only owns the prefs.
  Future<void> resetLearningDefaults() async {
    _ttsSpeed = 1.0;
    _dailyReminderEnabled = false;
    _dailyReminderHour = 19;
    _dailyReminderMinute = 0;
    _srsDesiredRetention = 0.9;
    await _appPrefs.setDouble(LocalStateKeys.ttsSpeed, 1.0);
    await _appPrefs.setBool(LocalStateKeys.dailyReminderEnabled, value: false);
    await _appPrefs.setInt(LocalStateKeys.dailyReminderHour, 19);
    await _appPrefs.setInt(LocalStateKeys.dailyReminderMinute, 0);
    await _appPrefs.setDouble(LocalStateKeys.srsDesiredRetention, 0.9);
    if (getIt.isRegistered<SrsProvider>()) {
      getIt<SrsProvider>().setDesiredRetention(0.9);
    }
    if (getIt.isRegistered<GrammarReviewProvider>()) {
      getIt<GrammarReviewProvider>().setDesiredRetention(0.9);
    }
    notifyListeners();
  }

  /// Restore legacy-compatibility (旧版与兼容性) prefs to their factory
  /// defaults. Never deletes user data — only the WebView JS tunable
  /// owned by the compatibility page.
  Future<void> resetLegacyCompatibilityDefaults() async {
    _ankiForceDisableJs = false;
    await _appPrefs.setBool(LocalStateKeys.ankiForceDisableJs, value: false);
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
