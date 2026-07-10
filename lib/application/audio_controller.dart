// Dart imports:
import 'dart:math';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/core/enums.dart';
import 'package:varnamala/courses/languages/swahili_vocab.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/gen/assets.gen.dart';
import 'package:varnamala/service/piper_swahili_tts.dart';
import 'package:varnamala/service/tts_availability_checker.dart';

@lazySingleton
class AudioController {
  final AudioPlayer _audioPlayer;
  final AudioPlayer _speechPlayer;
  final FlutterTts _tts;
  final LanguageProvider _languageProvider;
  final SettingsProvider _settingsProvider;
  final PiperSwahiliTts? _piperTts;
  final TtsAvailabilityChecker? _ttsChecker;
  final Random _random = Random();

  double _ttsSpeed = 1.0;
  double get ttsSpeed => _ttsSpeed;
  String? _lastTtsLanguage;

  AudioController(
    this._tts,
    this._languageProvider,
    this._settingsProvider, {
    @Named('audioPlayer') required AudioPlayer audioPlayer,
    @Named('speechPlayer') required AudioPlayer speechPlayer,
    PiperSwahiliTts? piperTts,
    TtsAvailabilityChecker? ttsChecker,
  })  : _audioPlayer = audioPlayer,
        _speechPlayer = speechPlayer,
        _piperTts = piperTts,
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
    getIt<SettingsProvider>().triggerHaptic(type);
  }

  Future<void> _playSound(String assetPath) async {
    if (!getIt<SettingsProvider>().soundEffectsEnabled) return;
    try {
      // need to remove the assets/ prefix from the asset path
      final String path = assetPath.replaceFirst('assets/', '');
      await _audioPlayer.play(
        AssetSource(path),
        mode: PlayerMode.lowLatency,
      );
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────
  // TTS / speech
  // ──────────────────────────────────────────────────────────────

  /// Prefers Google TTS on Android, then sets language for the current target.
  ///
  /// [setEngine] can reset the TTS service, so language is re-applied whenever
  /// the resolved locale differs from the last one used.
  Future<void> _ensureSystemTtsReady() async {
    final baseLang = _languageProvider.ttsLanguageCode;
    final checker = _ttsChecker;
    final wasConfigured = checker?.isEngineConfigured ?? true;

    String lang = baseLang;
    if (checker != null) {
      // resolveLanguageCode configures Google TTS first, then picks a locale
      // the engine actually reports as available (e.g. sw-KE).
      final resolved = await checker.resolveLanguageCode(baseLang);
      if (!wasConfigured) {
        // Engine may have been selected for the first time → force setLanguage.
        _lastTtsLanguage = null;
      }
      if (resolved != null) lang = resolved;
    }

    if (_lastTtsLanguage == lang) return;
    await _tts.setLanguage(lang);
    _lastTtsLanguage = lang;
  }

  /// Re-select Google TTS (if present) and clear the cached language so the
  /// next [speak] re-binds locale. Used when the user switches back to system
  /// TTS in settings.
  Future<void> rebindSystemTts() async {
    _lastTtsLanguage = null;
    await _ttsChecker?.configureSystemEngine(force: true);
  }

  /// Speak arbitrary [text] using TTS in the current target language.
  /// [speed] overrides the current global speed for this utterance.
  ///
  /// The source is chosen from [SettingsProvider.ttsEngine]:
  /// - [TtsEngine.system]: use the device's local TTS engine first (Google TTS
  ///   on Android when installed), then fall back to the bundled Piper model
  ///   for Swahili.
  /// - [TtsEngine.offline]: use the bundled Piper model first, then fall back
  ///   to the system TTS engine.
  Future<void> speak(String text, {double? speed}) async {
    if (text.isEmpty) return;

    final effectiveSpeed = speed ?? _ttsSpeed;
    final engine = _settingsProvider.ttsEngine;

    if (engine == TtsEngine.system) {
      try {
        await _ensureSystemTtsReady();
        await _tts.setSpeechRate(effectiveSpeed);
        await _tts.stop();
        debugPrint(
          'TTS route: system primary (lang=$_lastTtsLanguage, rate=$effectiveSpeed)',
        );
        await _tts.speak(text);
        return;
      } catch (e) {
        debugPrint('TTS route: system failed → piper fallback: $e');
      }
    }

    final piper = _piperTts;
    if (piper != null &&
        _languageProvider.selectedLanguage == TargetLanguage.swahili) {
      try {
        debugPrint(
          engine == TtsEngine.offline
              ? 'TTS route: offline primary (piper, rate=$effectiveSpeed)'
              : 'TTS route: piper fallback (rate=$effectiveSpeed)',
        );
        await piper.speak(text, speed: effectiveSpeed);
        return;
      } catch (e) {
        debugPrint('Piper Swahili TTS failed: $e');
      }
    }

    // If the user explicitly chose offline but Piper is unavailable, still
    // try the system TTS so the user gets some feedback instead of silence.
    if (engine == TtsEngine.offline) {
      try {
        await _ensureSystemTtsReady();
        await _tts.setSpeechRate(effectiveSpeed);
        await _tts.stop();
        debugPrint(
          'TTS route: offline failed → system fallback (lang=$_lastTtsLanguage)',
        );
        await _tts.speak(text);
      } catch (e) {
        debugPrint('Offline fallback also failed: $e');
      }
    }
  }

  /// Play a pre-recorded audio asset. [assetPath] is expected to start with
  /// `assets/`; the prefix is stripped before passing to [AudioPlayer].
  Future<void> speakFromAsset(String assetPath) async {
    try {
      final String path = assetPath.replaceFirst('assets/', '');
      await _speechPlayer.stop();
      await _speechPlayer.play(AssetSource(path));
    } catch (e) {
      debugPrint('Error playing asset audio: $e');
    }
  }

  /// Speak a vocabulary word. Prefers the offline [audioAsset] if present,
  /// otherwise falls back to TTS of the word term.
  Future<void> speakWord(String wordId) async {
    final entry = swahiliVocabById[wordId];
    if (entry?.audioAsset?.isNotEmpty == true) {
      await speakFromAsset(entry!.audioAsset!);
      return;
    }
    await speak(entry?.term ?? wordId);
  }

  /// Set the global TTS speed. Clamped to [0.5, 2.0].
  void setTtsSpeed(double speed) {
    _ttsSpeed = speed.clamp(0.5, 2.0);
  }
}
