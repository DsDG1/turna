// Dart imports:
import 'dart:math';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/accessibility_provider.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/domain/audio/anki_audio_resolver.dart';
import 'package:varnamala/domain/audio/vocab_audio_resolver.dart';
import 'package:varnamala/gen/assets.gen.dart';
import 'package:varnamala/service/tts_availability_checker.dart';

/// Which backend actually produced the last [AudioController.speak] utterance.
enum TtsSpeakSource {
  system,
  failed,
}

/// Result of [AudioController.speakWithResult] for settings UI / debugging.
class TtsSpeakResult {
  const TtsSpeakResult({
    required this.source,
    this.error,
    this.usedFallback = false,
  });

  final TtsSpeakSource source;
  final String? error;

  /// True when the preferred engine failed and a secondary engine spoke.
  /// Always `false` in this build (system TTS only — no fallback).
  final bool usedFallback;

  String get userLabel {
    switch (source) {
      case TtsSpeakSource.system:
        return 'Google / system TTS';
      case TtsSpeakSource.failed:
        return 'No voice played';
    }
  }
}

@lazySingleton
class AudioController {
  final AudioPlayer _audioPlayer;
  final AudioPlayer _speechPlayer;
  final FlutterTts _tts;
  final LanguageProvider _languageProvider;
  final SettingsProvider _settingsProvider;
  final AccessibilityProvider _accessibilityProvider;
  final VocabAudioResolver _vocabAudioResolver;
  final AnkiAudioResolver _ankiMediaResolver = AnkiAudioResolver();
  final TtsAvailabilityChecker? _ttsChecker;
  final Random _random = Random();

  double _ttsSpeed = 1.0;
  double get ttsSpeed => _ttsSpeed;
  String? _lastTtsLanguage;
  double? _lastTtsRate;

  TtsSpeakResult? _lastSpeakResult;
  TtsSpeakResult? get lastSpeakResult => _lastSpeakResult;

  AudioController(
    this._tts,
    this._languageProvider,
    this._settingsProvider,
    this._accessibilityProvider,
    this._vocabAudioResolver, {
    @Named('audioPlayer') required AudioPlayer audioPlayer,
    @Named('speechPlayer') required AudioPlayer speechPlayer,
    TtsAvailabilityChecker? ttsChecker,
  })  : _audioPlayer = audioPlayer,
        _speechPlayer = speechPlayer,
        _ttsChecker = ttsChecker {
    _ttsSpeed = _settingsProvider.ttsSpeed;
  }

  // List of error sound assets
  final List<String> _errorSounds = [
    Assets.sounds.error1,
    Assets.sounds.error2,
    Assets.sounds.error3,
    Assets.sounds.error4,
  ];

  // List of level-up sound assets
  final List<String> _levelUpSounds = [
    Assets.sounds.levelUp1,
    Assets.sounds.levelUp2,
    Assets.sounds.levelUp3,
    Assets.sounds.levelUp4,
  ];

  Future<void> playRandomErrorSound() async {
    _triggerHaptic(HapticFeedbackType.heavy);
    final index = _random.nextInt(_errorSounds.length);
    final selectedErrorSound = _errorSounds[index];
    await _playSound(selectedErrorSound);
  }

  Future<void> playRandomLevelUpSound() async {
    _triggerHaptic(HapticFeedbackType.medium);
    final index = _random.nextInt(_levelUpSounds.length);
    final selectedLevelUpSound = _levelUpSounds[index];
    await _playSound(selectedLevelUpSound);
  }

  void _triggerHaptic(HapticFeedbackType type) {
    // Sensory-reduce silences non-essential haptics, independent of the
    // explicit haptic toggle in SettingsProvider.
    if (_accessibilityProvider.quietFeedback) return;
    _settingsProvider.triggerHaptic(type);
  }

  Future<void> _playSound(String assetPath) async {
    // Sensory-reduce mutes non-essential sound effects (error / level-up
    // cues), independent of the explicit sound-effects toggle.
    if (!_settingsProvider.soundEffectsEnabled) return;
    if (_accessibilityProvider.quietFeedback) return;
    try {
      await _audioPlayer.play(
        AssetSource(normalizeAssetPath(assetPath)),
        mode: PlayerMode.lowLatency,
      );
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────
  // TTS / speech
  // ──────────────────────────────────────────────────────────────

  /// Maps UI speed multipliers (0.5–2.0, where 1.0 = normal) to flutter_tts
  /// [setSpeechRate] values.
  ///
  /// flutter_tts documents normal speech as **0.5** on both Android and iOS
  /// (Android multiplies by 2.0 internally so 0.5 → native 1.0). Passing the
  /// UI value 1.0 directly would speak at ~2× normal speed.
  @visibleForTesting
  static double mapUiSpeedToFlutterTtsRate(double uiSpeed) {
    final clamped = uiSpeed.clamp(0.5, 2.0);
    return (0.5 * clamped).clamp(0.0, 1.5);
  }

  static bool _isTruthyResult(dynamic value) {
    if (value == null) return true; // some platforms return null on success
    if (value is bool) return value;
    if (value is num) return value != 0;
    return true;
  }

  /// Prefers Google TTS on Android, then sets language for the current target.
  ///
  /// Throws [StateError] when no usable system locale can be bound so the
  /// caller can report the failure instead of speaking with the wrong voice.
  Future<void> _ensureSystemTtsReady() async {
    final baseLang = _languageProvider.ttsLanguageCode;
    final checker = _ttsChecker;
    final wasConfigured = checker?.isEngineConfigured ?? true;

    String? lang;
    if (checker != null) {
      // resolveLanguageCode configures Google TTS first, then picks a locale
      // the engine actually reports as available (e.g. tr-TR).
      lang = await checker.resolveLanguageCode(baseLang);
      if (!wasConfigured) {
        // Engine may have been selected for the first time → force setLanguage.
        _lastTtsLanguage = null;
      }
    } else {
      lang = baseLang;
    }

    if (lang == null) {
      throw StateError(
        'No system TTS locale available for "$baseLang" '
        '(install Google TTS + Turkish voice data)',
      );
    }

    if (_lastTtsLanguage == lang) return;

    final result = await _tts.setLanguage(lang);
    if (!_isTruthyResult(result)) {
      _lastTtsLanguage = null;
      throw StateError(
        'setLanguage("$lang") failed — language missing or not installed',
      );
    }
    _lastTtsLanguage = lang;
    debugPrint('AudioController: system TTS language bound to "$lang"');
  }

  /// Re-select Google TTS (if present) and clear the cached language so the
  /// next [speak] re-binds locale. Used when the user revisits TTS settings.
  Future<void> rebindSystemTts() async {
    _lastTtsLanguage = null;
    await _ttsChecker?.configureSystemEngine(force: true);
  }

  /// Stop any in-progress system TTS.
  Future<void> stopSystemTts() async {
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('AudioController: stopSystemTts failed: $e');
    }
  }

  Future<void> _speakWithSystemTts(String text, double effectiveSpeed) async {
    await _ensureSystemTtsReady();
    final rate = mapUiSpeedToFlutterTtsRate(effectiveSpeed);
    if (_lastTtsRate != rate) {
      await _tts.setSpeechRate(rate);
      _lastTtsRate = rate;
    }
    await _tts.stop();
    debugPrint(
      'TTS route: system (lang=$_lastTtsLanguage, '
      'uiSpeed=$effectiveSpeed, flutterRate=$rate)',
    );
    final result = await _tts.speak(text);
    if (result == false || result == 0) {
      throw StateError('system TTS speak() returned failure ($result)');
    }
  }

  /// Speak arbitrary [text] using TTS in the current target language.
  /// [speed] overrides the current global speed for this utterance.
  ///
  /// See [speakWithResult] when the caller needs to know which engine spoke.
  Future<void> speak(String text, {double? speed}) async {
    await speakWithResult(text, speed: speed);
  }

  /// Like [speak], but returns which backend produced audio.
  ///
  /// This build routes through the device/Google system TTS only. If it
  /// fails, [TtsSpeakSource.failed] is returned with the error — there is no
  /// offline fallback in this build.
  Future<TtsSpeakResult> speakWithResult(String text, {double? speed}) async {
    if (text.isEmpty) {
      const empty = TtsSpeakResult(
        source: TtsSpeakSource.failed,
        error: 'empty text',
      );
      _lastSpeakResult = empty;
      return empty;
    }

    final effectiveSpeed = speed ?? _ttsSpeed;

    try {
      await _speakWithSystemTts(text, effectiveSpeed);
      const ok = TtsSpeakResult(source: TtsSpeakSource.system);
      _lastSpeakResult = ok;
      debugPrint('TTS route: system OK');
      return ok;
    } catch (e) {
      debugPrint('TTS route: system failed: $e');
      final fail = TtsSpeakResult(
        source: TtsSpeakSource.failed,
        error: 'system: $e',
      );
      _lastSpeakResult = fail;
      return fail;
    }
  }

  /// Whether [ref] looks like a bundled asset path rather than a logical id.
  ///
  /// Paths contain `/` or start with `assets`; vocab word ids are bare tokens.
  @visibleForTesting
  static bool isAssetPath(String ref) {
    final t = ref.trim();
    return t.contains('/') || t.startsWith('assets');
  }

  /// Strip leading `/` and optional `assets/` so [AssetSource] gets a relative
  /// path (e.g. `audio/turkish/test.mp3`).
  @visibleForTesting
  static String normalizeAssetPath(String assetPath) {
    var path = assetPath.trim();
    if (path.startsWith('/')) {
      path = path.substring(1);
    }
    if (path.startsWith('assets/')) {
      path = path.substring('assets/'.length);
    }
    return path;
  }

  /// Play a pre-recorded audio asset. Accepts paths with or without an
  /// `assets/` prefix (and optional leading `/`); normalization is applied
  /// before passing to [AudioPlayer].
  Future<void> speakFromAsset(String assetPath) async {
    try {
      await _speechPlayer.stop();
      await _speechPlayer.play(AssetSource(normalizeAssetPath(assetPath)));
    } catch (e) {
      debugPrint('Error playing asset audio: $e');
    }
  }

  /// Speak a vocabulary word. Prefers the offline [audioAsset] if present,
  /// otherwise falls back to TTS of the word term.
  ///
  /// `anki://<importId>/<file>` references (Anki deck media) are resolved to
  /// the on-disk copy and played directly — never sent to TTS.
  ///
  /// Content lookup goes through [VocabAudioResolver] so this class does not
  /// import language-specific vocab maps.
  Future<void> speakWord(String wordId) async {
    if (AnkiAudioResolver.isAnkiAsset(wordId)) {
      await _playAnkiMedia(wordId);
      return;
    }
    final resolved = _vocabAudioResolver.resolve(wordId);
    final asset = resolved.audioAsset;
    if (asset != null && asset.isNotEmpty) {
      await speakFromAsset(asset);
      return;
    }
    await speak(resolved.speakText);
  }

  /// Play an Anki deck media file (`anki://` reference) from its persistent
  /// copy. Missing files degrade silently (the reference may predate the
  /// media copy or the deck may have been uninstalled).
  Future<void> _playAnkiMedia(String ref) async {
    try {
      final path = await _ankiMediaResolver.resolveMediaPath(ref);
      if (path == null) return;
      await _speechPlayer.stop();
      await _speechPlayer.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint('Error playing Anki media: $e');
    }
  }

  /// Listen-only / mixed content helper: [audioAsset] may be an asset path or
  /// a logical word id. Path detection lives here so renderers only call this
  /// (or plain [speak] / [speakFromAsset] / [speakWord]).
  Future<void> speakListenContent({
    String? audioAsset,
    String transcript = '',
  }) async {
    final asset = audioAsset?.trim();
    final text = transcript.trim();

    if (asset != null && asset.isNotEmpty) {
      if (isAssetPath(asset)) {
        await speakFromAsset(asset);
      } else if (text.isNotEmpty) {
        // Prefer readable transcript for TTS when asset is a logical id
        // without an offline path.
        await speak(text);
      } else {
        await speakWord(asset);
      }
    } else if (text.isNotEmpty) {
      await speak(text);
    }
  }

  /// Set the global TTS speed. Clamped to [0.5, 2.0].
  void setTtsSpeed(double speed) {
    _ttsSpeed = speed.clamp(0.5, 2.0);
  }
}