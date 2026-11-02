// Dart imports:
import 'dart:math';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/course_pack/course_pack_media.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/core/html_stripper.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/domain/audio/anki_audio_resolver.dart';
import 'package:turna/domain/audio/vocab_audio_resolver.dart';
import 'package:turna/gen/assets.gen.dart';
import 'package:turna/service/audio_backend.dart';
import 'package:turna/service/speech_backend.dart';
import 'package:turna/service/tts_availability_checker.dart';

/// Which backend actually produced the last [AudioController.speak] utterance.
enum TtsSpeakSource {
  system,
  failed,
  cancelled,
}

enum TtsFailureReason {
  voiceMissing,
  engineUnavailable,
  synthesisFailed,
  timeout,
  emptyText,
  unknown,
}

/// Result of [AudioController.speakWithResult] for settings UI / debugging.
class TtsSpeakResult {
  const TtsSpeakResult({
    required this.source,
    this.failureReason,
    this.error,
    this.usedFallback = false,
  });

  final TtsSpeakSource source;
  final TtsFailureReason? failureReason;
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
      case TtsSpeakSource.cancelled:
        return 'Playback cancelled';
    }
  }
}

@lazySingleton
class AudioController {
  final AudioBackend _effects;
  final AudioBackend _speech;
  final SpeechBackend _tts;

  final LanguageProvider _languageProvider;
  final SettingsProvider _settingsProvider;
  final AccessibilityProvider _accessibilityProvider;
  final VocabAudioResolver _vocabAudioResolver;
  final AnkiAudioResolver _ankiMediaResolver;
  final TtsAvailabilityChecker? _ttsChecker;
  final Random _random = Random();

  double _ttsSpeed = 1.0;
  double get ttsSpeed => _ttsSpeed;
  String? _lastTtsLanguage;
  double? _lastTtsRate;
  Future<void> _ttsQueue = Future<void>.value();
  int _ttsRequestId = 0;

  TtsSpeakResult? _lastSpeakResult;
  TtsSpeakResult? get lastSpeakResult => _lastSpeakResult;

  final ValueNotifier<bool> _speaking = ValueNotifier(false);
  int _speakingDepth = 0;

  /// True while TTS or a speech asset is in flight.
  bool get isSpeaking => _speaking.value;

  ValueListenable<bool> get speakingListenable => _speaking;

  Future<T> _trackSpeaking<T>(Future<T> Function() run) async {
    _speakingDepth++;
    _speaking.value = true;
    try {
      return await run();
    } finally {
      _speakingDepth--;
      if (_speakingDepth <= 0) {
        _speakingDepth = 0;
        _speaking.value = false;
      }
    }
  }

  AudioController(
    this._tts,
    this._languageProvider,
    this._settingsProvider,
    this._accessibilityProvider,
    this._vocabAudioResolver, {
    @Named('effectsAudio') required AudioBackend effects,
    @Named('speechAudio') required AudioBackend speech,
    TtsAvailabilityChecker? ttsChecker,
    AnkiAudioResolver? ankiMediaResolver,
  })  : _effects = effects,
        _speech = speech,
        _ttsChecker = ttsChecker,
        _ankiMediaResolver = ankiMediaResolver ?? AnkiAudioResolver() {
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
    //
    // Each gate says which one stopped it. These are silent returns by design —
    // muting is not an error — but two silent returns, a call that was never
    // made, and a call that succeeded with nothing audible all look identical
    // in the log, which is exactly what a device run cannot tell apart.
    if (!_settingsProvider.soundEffectsEnabled) {
      logger.d('Audio: skipped $assetPath (sound effects off)');
      return;
    }
    if (_accessibilityProvider.quietFeedback) {
      logger.d('Audio: skipped $assetPath (sensory-reduce)');
      return;
    }
    await playIgnoringFailure(
      () => _effects.playAsset(normalizeAssetPath(assetPath)),
      what: 'sound effect $assetPath',
    );
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

  /// Prefers Google TTS on Android, then sets language for the current target.
  ///
  /// Throws [StateError] when no usable system locale can be bound so the
  /// caller can report the failure instead of speaking with the wrong voice.
  Future<void> _ensureSystemTtsReady({String? languageCode}) async {
    final targetBase = _languageProvider.ttsLanguageCode;
    final baseLang = languageCode ?? targetBase;
    final checker = _ttsChecker;
    final wasConfigured = checker?.isEngineConfigured ?? true;

    String? lang;
    if (checker != null) {
      // resolveLanguageCode configures Google TTS first, then picks a locale
      // the engine actually reports as available (e.g. tr-TR).
      lang = await checker.resolveLanguageCode(baseLang);
      // If the requested (e.g. auto-detected) language has no installed voice,
      // fall back to the target language so the user still hears something.
      if (lang == null && baseLang != targetBase) {
        lang = await checker.resolveLanguageCode(targetBase);
      }
      if (!wasConfigured) {
        // Engine may have been selected for the first time → force setLanguage.
        _lastTtsLanguage = null;
      }
    } else {
      lang = baseLang;
    }

    if (lang == null) {
      // Android has a concrete remedy — install Google TTS plus the voice data
      // for that language — and dropping it turns an actionable message into a
      // bare statement of fact. It is withheld on the companion build, where
      // there is no store to install from and no engine to choose: the settings
      // tile carries that platform's wording instead.
      final remedy = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? ' (install Google TTS + voice data for that language)'
          : '';
      throw StateError('no system TTS locale available for "$baseLang"$remedy');
    }

    if (_lastTtsLanguage == lang) return;

    final bound = await _tts.bindLanguage(lang);
    if (!bound) {
      _lastTtsLanguage = null;
      throw StateError(
        'setLanguage("$lang") failed — language missing or not installed',
      );
    }
    _lastTtsLanguage = lang;
    logger.d('AudioController: system TTS language bound to "$lang"');
  }

  /// Re-select Google TTS (if present) and clear the cached language so the
  /// next [speak] re-binds locale. Used when the user revisits TTS settings.
  Future<void> rebindSystemTts() async {
    _lastTtsLanguage = null;
    await _ttsChecker?.configureSystemEngine(force: true);
  }

  /// Stop any in-progress system TTS and invalidate queued utterances.
  Future<void> stopSystemTts() async {
    _ttsRequestId++;
    await _stopTts();
  }

  Future<void> _stopTts() async {
    try {
      await _tts.stop();
    } catch (e) {
      logger.w('AudioController: stopSystemTts failed: $e');
    }
  }

  /// Stop the media speech player and release its file source. The player
  /// holds open handles to `anki_media` files, which
  /// otherwise keeps a deck's media undeletable on uninstall — call this
  /// before deleting media files.
  Future<void> stopSpeechPlayer() async {
    try {
      await _speech.stop();
      await _speech.release();
    } catch (e) {
      logger.w('AudioController: stopSpeechPlayer failed: $e');
    }
  }

  Future<void> _speakWithSystemTts(
    int requestId,
    String text,
    double effectiveSpeed, {
    String? languageCode,
  }) async {
    await _ensureSystemTtsReady(languageCode: languageCode);
    final rate = mapUiSpeedToFlutterTtsRate(effectiveSpeed);
    if (_lastTtsRate != rate) {
      await _tts.setRate(rate);
      _lastTtsRate = rate;
    }
    // The engine is created lazily per platform: `flutter_tts` needs nothing,
    // while the companion build has to bring one up before it can speak. Doing
    // it here rather than at startup keeps a device with no usable voice from
    // paying for an engine it will never use.
    await _tts.init(language: _lastTtsLanguage);
    if (requestId != _ttsRequestId) return;
    logger.d(
      'TTS route: system (lang=$_lastTtsLanguage, '
      'uiSpeed=$effectiveSpeed, flutterRate=$rate)',
    );
    final spoken = await _tts.speak(text);
    if (!spoken) {
      throw StateError('system TTS speak() returned failure');
    }
  }

  /// Speak arbitrary [text] using TTS in the current target language.
  /// [speed] overrides the current global speed for this utterance.
  ///
  /// Pass [languageCode] (BCP-47 base code, e.g. `zh`, `en`) to speak in a
  /// non-target voice - used by smart language detection for content whose
  /// language varies per item (MCQ options, Anki card faces, dictionary
  /// translations). When null the target-language voice is used.
  ///
  /// See [speakWithResult] when the caller needs to know which engine spoke.
  Future<void> speak(String text, {double? speed, String? languageCode}) async {
    await speakWithResult(text, speed: speed, languageCode: languageCode);
  }

  /// Like [speak], but returns which backend produced audio.
  Future<TtsSpeakResult> speakWithResult(
    String text, {
    double? speed,
    String? languageCode,
  }) {
    final cleanText = stripHtml(text).trim();
    if (cleanText.isEmpty) {
      const empty = TtsSpeakResult(
        source: TtsSpeakSource.failed,
        failureReason: TtsFailureReason.emptyText,
        error: 'empty text',
      );
      _lastSpeakResult = empty;
      return Future<TtsSpeakResult>.value(empty);
    }

    final requestId = ++_ttsRequestId;
    final stopPrevious = _stopTts();
    final operation = _ttsQueue.then((_) => stopPrevious).then(
          (_) => _speakWithResult(
            requestId,
            cleanText,
            speed: speed,
            languageCode: languageCode,
          ),
        );
    _ttsQueue = operation.then((_) {}, onError: (Object e, StackTrace st) {
      logger.w('AudioController: queued TTS failed: $e', stackTrace: st);
    });
    return _trackSpeaking(() => operation);
  }

  Future<TtsSpeakResult> _speakWithResult(
    int requestId,
    String text, {
    double? speed,
    String? languageCode,
  }) async {
    if (requestId != _ttsRequestId) {
      return const TtsSpeakResult(source: TtsSpeakSource.cancelled);
    }
    final effectiveSpeed = speed ?? _ttsSpeed;
    try {
      await _speakWithSystemTts(
        requestId,
        text,
        effectiveSpeed,
        languageCode: languageCode,
      );
      if (requestId != _ttsRequestId) {
        return const TtsSpeakResult(source: TtsSpeakSource.cancelled);
      }
      const ok = TtsSpeakResult(source: TtsSpeakSource.system);
      _lastSpeakResult = ok;
      logger.d('TTS route: system OK');
      return ok;
    } on TtsPlaybackException catch (e) {
      return _speakFailed(
        requestId,
        e.kind == TtsPlaybackErrorKind.timeout
            ? TtsFailureReason.timeout
            : TtsFailureReason.synthesisFailed,
        e,
      );
    } catch (e) {
      final message = e.toString();
      final reason = _ttsChecker?.isEngineConfigured == false
          ? TtsFailureReason.engineUnavailable
          : message.contains('no system TTS locale') ||
                  message.contains('setLanguage')
              ? TtsFailureReason.voiceMissing
              : TtsFailureReason.unknown;
      if (reason == TtsFailureReason.voiceMissing ||
          reason == TtsFailureReason.engineUnavailable) {
        await rebindSystemTts();
      }
      return _speakFailed(requestId, reason, e);
    }
  }

  TtsSpeakResult _speakFailed(
    int requestId,
    TtsFailureReason reason,
    Object error,
  ) {
    if (requestId != _ttsRequestId) {
      return const TtsSpeakResult(source: TtsSpeakSource.cancelled);
    }
    logger.w('TTS route: system failed (${reason.name}): $error');
    final fail = TtsSpeakResult(
      source: TtsSpeakSource.failed,
      failureReason: reason,
      error: '$error',
    );
    _lastSpeakResult = fail;
    return fail;
  }

  /// Whether [ref] looks like a bundled asset path rather than a logical id.
  ///
  /// Paths contain `/` or start with `assets`; vocab word ids are bare tokens.
  @visibleForTesting
  static bool isAssetPath(String ref) {
    final t = ref.trim();
    return t.contains('/') || t.startsWith('assets');
  }

  /// Strip leading `/` and optional `assets/` so [AudioBackend.playAsset] gets a relative
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
  /// before passing to [AudioBackend].
  Future<void> speakFromAsset(String assetPath) async {
    await _trackSpeaking(() async {
      try {
        await _speech.stop();
        await _speech.playAsset(normalizeAssetPath(assetPath));
      } catch (e) {
        logger.w('Error playing asset audio: $e');
      }
    });
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
    await _trackSpeaking(() => _speakWord(wordId));
  }

  Future<TtsSpeakResult> speakWordWithResult(String wordId) async {
    return _trackSpeaking(() => _speakWordWithResult(wordId));
  }

  Future<void> _speakWord(String wordId) async {
    await _speakWordWithResult(wordId);
  }

  Future<TtsSpeakResult> _speakWordWithResult(String wordId) async {
    if (AnkiAudioResolver.isAnkiAsset(wordId)) {
      return _mediaSpeakResult(await playAnkiMedia(wordId));
    }
    if (CoursePackMedia.isPackAsset(wordId)) {
      return _mediaSpeakResult(await playCoursePackMedia(wordId));
    }
    final resolved = _vocabAudioResolver.resolve(wordId);
    final asset = resolved.audioAsset;
    if (asset != null && asset.isNotEmpty) {
      if (CoursePackMedia.isPackAsset(asset)) {
        if (await playCoursePackMedia(asset)) {
          return const TtsSpeakResult(source: TtsSpeakSource.system);
        }
        // Extracted media missing (e.g. backup restored without the
        // imported_courses tree) — fall through to TTS on the term.
      } else {
        await speakFromAsset(asset);
        return const TtsSpeakResult(source: TtsSpeakSource.system);
      }
    }
    if (await playOfficialMediaFile(wordId)) {
      return const TtsSpeakResult(source: TtsSpeakSource.system);
    }
    return speakWithResult(resolved.speakText);
  }

  TtsSpeakResult _mediaSpeakResult(bool played) {
    return played
        ? const TtsSpeakResult(source: TtsSpeakSource.system)
        : const TtsSpeakResult(
            source: TtsSpeakSource.failed,
            failureReason: TtsFailureReason.unknown,
            error: 'media playback failed',
          );
  }

  /// P5F-23: official-collection media reaches projected interactions as a
  /// bare filename (`hello.mp3`). When the official Anki collection is
  /// available, resolve it against `collection.media` and play the local
  /// file instead of TTS-reading the filename. Returns true when playback
  /// started.
  Future<bool> playOfficialMediaFile(String rawName) async {
    final file = officialAnkiMediaCandidateFile(
      rawName,
      OfficialAnkiCompositionRoot.locatorPaths,
    );
    if (file == null) return false;
    try {
      await _speech.stop();
      await _speech.playFile(file.path);
      return true;
    } catch (e) {
      logger.w('Error playing official Anki media: $e');
      return false;
    }
  }

  /// Resolve a bare official-collection media filename to an on-disk path,
  /// without playing it. Used by image strips, which need the file rather than
  /// playback. Same boundary checks as [playOfficialMediaFile].
  Future<String?> resolveOfficialMediaPath(String rawName) async {
    return officialAnkiMediaCandidateFile(
      rawName,
      OfficialAnkiCompositionRoot.locatorPaths,
    )?.path;
  }

  /// Play an imported course-pack media file (`turnapack://` reference).
  Future<bool> playCoursePackMedia(String ref) async {
    if (!CoursePackMedia.isPackAsset(ref)) return false;
    try {
      final path = await CoursePackMedia.resolveFile(ref);
      if (path == null) return false;
      await _speech.stop();
      await _speech.playFile(path);
      return true;
    } catch (e) {
      logger.w('Error playing course-pack media: $e');
      return false;
    }
  }

  /// Play an Anki deck media file (`anki://` reference) from its persistent
  /// copy. Returns `true` only when playback was successfully started.
  /// Missing files and platform playback errors never fall back to TTS.
  Future<bool> playAnkiMedia(String ref) async {
    if (!AnkiAudioResolver.isAnkiAsset(ref)) return false;
    try {
      final path = await _ankiMediaResolver.resolveMediaPath(ref);
      if (path == null) return false;
      await _speech.stop();
      await _speech.playFile(path);
      return true;
    } catch (e) {
      logger.w('Error playing Anki media: $e');
      return false;
    }
  }

  /// Listen-only / mixed content helper: [audioAsset] may be an asset path or
  /// a logical word id. Path detection lives here so renderers only call this
  /// (or plain [speak] / [speakFromAsset] / [speakWord]).
  Future<void> speakListenContent({
    String? audioAsset,
    String transcript = '',
  }) async {
    await speakListenContentWithResult(
      audioAsset: audioAsset,
      transcript: transcript,
    );
  }

  Future<TtsSpeakResult> speakListenContentWithResult({
    String? audioAsset,
    String transcript = '',
  }) async {
    return _trackSpeaking(
      () => _speakListenContentWithResult(
        audioAsset: audioAsset,
        transcript: transcript,
      ),
    );
  }

  Future<TtsSpeakResult> _speakListenContentWithResult({
    String? audioAsset,
    String transcript = '',
  }) async {
    final asset = audioAsset?.trim();
    final text = transcript.trim();

    if (asset != null && asset.isNotEmpty) {
      if (AnkiAudioResolver.isAnkiAsset(asset)) {
        return _mediaSpeakResult(await playAnkiMedia(asset));
      } else if (CoursePackMedia.isPackAsset(asset)) {
        if (await playCoursePackMedia(asset)) {
          return const TtsSpeakResult(source: TtsSpeakSource.system);
        }
        if (text.isNotEmpty) return speakWithResult(text);
        return _mediaSpeakResult(false);
      } else if (isAssetPath(asset)) {
        await speakFromAsset(asset);
        return const TtsSpeakResult(source: TtsSpeakSource.system);
      } else if (await playOfficialMediaFile(asset)) {
        return const TtsSpeakResult(source: TtsSpeakSource.system);
      } else if (text.isNotEmpty) {
        return speakWithResult(text);
      } else {
        return speakWordWithResult(asset);
      }
    } else if (text.isNotEmpty) {
      return speakWithResult(text);
    }
    return const TtsSpeakResult(
      source: TtsSpeakSource.failed,
      failureReason: TtsFailureReason.emptyText,
      error: 'empty text',
    );
  }

  /// Set the global TTS speed. Clamped to [0.5, 2.0].
  void setTtsSpeed(double speed) {
    _ttsSpeed = speed.clamp(0.5, 2.0);
  }
}
