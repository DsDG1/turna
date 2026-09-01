// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/service/locator.dart';

/// App-wide accessibility / neurodiversity settings that persist across
/// launches and are consumed app-wide via [ChangeNotifier].
///
/// Surfaces a small set of toggles tuned for neurodivergent learners
/// (ADHD, sensory sensitivity, autism spectrum):
///  * [textScale]         — magnify text 100%–200%.
///  * [cardTextScale]     — magnify card content 100%–200% (WebView cards
///                          included, opt-in: 100% leaves cards untouched).
///  * [reducedMotion]     — shorten/disable animations.
///  * [highContrast]      — switch to a high-contrast theme variant.
///  * [sensoryReduce]     — mute non-essential sounds and haptics.
///  * [focusMode]         — hide decorative animations / visual noise.
///
/// Persistence follows the [SettingsProvider] recipe: keys live in
/// [LocalStateKeys], reads happen in [_load], setters persist then notify.
@lazySingleton
class AccessibilityProvider extends ChangeNotifier {
  final AppPrefs _appPrefs;

  int _textScale = 100;
  int _cardTextScale = 100;
  bool _reducedMotion = false;
  bool _highContrast = false;
  bool _sensoryReduce = false;
  bool _focusMode = false;

  AccessibilityProvider(this._appPrefs) {
    _load();
  }

  int get textScale => _textScale;
  int get cardTextScale => _cardTextScale;
  bool get reducedMotion => _reducedMotion;
  bool get highContrast => _highContrast;
  bool get sensoryReduce => _sensoryReduce;
  bool get focusMode => _focusMode;

  /// [TextScaler] derived from [textScale] (100% → 1.0x, 200% → 2.0x).
  TextScaler get textScaler => TextScaler.linear(_textScale / 100.0);

  /// Convenience for audio/haptic controllers: treat sensory-reduce as a
  /// single "quiet the feedback" signal independent of the sound/haptic
  /// toggles in [SettingsProvider].
  bool get quietFeedback => _sensoryReduce;

  void _load() {
    _textScale = _appPrefs.preferences
        .getInt(LocalStateKeys.textScale, defaultValue: 100)
        .getValue();
    _cardTextScale = _appPrefs.preferences
        .getInt(LocalStateKeys.cardTextScale, defaultValue: 100)
        .getValue();
    _reducedMotion = _appPrefs.preferences
        .getBool(LocalStateKeys.reducedMotion, defaultValue: false)
        .getValue();
    _highContrast = _appPrefs.preferences
        .getBool(LocalStateKeys.highContrast, defaultValue: false)
        .getValue();
    _sensoryReduce = _appPrefs.preferences
        .getBool(LocalStateKeys.sensoryReduce, defaultValue: false)
        .getValue();
    _focusMode = _appPrefs.preferences
        .getBool(LocalStateKeys.focusMode, defaultValue: false)
        .getValue();
  }

  /// Re-reads every accessibility pref and notifies listeners. Used after a
  /// backup restore so the running theme matches the restored snapshot
  /// without an app restart (PostRestoreReloadRegistry step).
  void reload() {
    _load();
    notifyListeners();
  }

  Future<void> setTextScale(int value) async {
    final clamped = value.clamp(100, 200);
    _textScale = clamped;
    await _appPrefs.setInt(LocalStateKeys.textScale, clamped);
    notifyListeners();
  }

  Future<void> setCardTextScale(int value) async {
    final clamped = value.clamp(100, 200);
    _cardTextScale = clamped;
    await _appPrefs.setInt(LocalStateKeys.cardTextScale, clamped);
    notifyListeners();
  }

  /// Live-preview variants used while a settings slider is being dragged:
  /// update the in-memory value and notify so the app reacts immediately, but
  /// leave persistence to the drag-end setter. Slider divisions throttle the
  /// calls to one per snapped step, so this never writes prefs per frame.
  void previewTextScale(int value) {
    final clamped = value.clamp(100, 200);
    if (_textScale == clamped) return;
    _textScale = clamped;
    notifyListeners();
  }

  void previewCardTextScale(int value) {
    final clamped = value.clamp(100, 200);
    if (_cardTextScale == clamped) return;
    _cardTextScale = clamped;
    notifyListeners();
  }

  Future<void> setReducedMotion(bool value) async {
    _reducedMotion = value;
    await _appPrefs.setBool(LocalStateKeys.reducedMotion, value: value);
    notifyListeners();
  }

  Future<void> setHighContrast(bool value) async {
    _highContrast = value;
    await _appPrefs.setBool(LocalStateKeys.highContrast, value: value);
    notifyListeners();
  }

  Future<void> setSensoryReduce(bool value) async {
    _sensoryReduce = value;
    await _appPrefs.setBool(LocalStateKeys.sensoryReduce, value: value);
    notifyListeners();
  }

  Future<void> setFocusMode(bool value) async {
    _focusMode = value;
    await _appPrefs.setBool(LocalStateKeys.focusMode, value: value);
    notifyListeners();
  }
}
