// Dart imports:
import 'dart:math';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/application/language_provider.dart';
import 'package:words625/courses/languages/kannada_vocab.dart';
import 'package:words625/gen/assets.gen.dart';

@lazySingleton
class AudioController {
  final AudioPlayer _audioPlayer;
  final AudioPlayer _speechPlayer;
  final FlutterTts _tts;
  final LanguageProvider _languageProvider;
  final Random _random = Random();

  double _ttsSpeed = 1.0;
  double get ttsSpeed => _ttsSpeed;
  String? _lastTtsLanguage;

  AudioController(
    this._tts,
    this._languageProvider, {
    AudioPlayer? audioPlayer,
    AudioPlayer? speechPlayer,
  })  : _audioPlayer = audioPlayer ?? AudioPlayer(),
        _speechPlayer = speechPlayer ?? AudioPlayer();

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
    int index = _random.nextInt(_errorSounds.length);
    String selectedErrorSound = _errorSounds[index];
    await _playSound(selectedErrorSound);
  }

  Future<void> playRandomLevelUpSound() async {
    int index = _random.nextInt(_levelUpSounds.length);
    String selectedLevelUpSound = _levelUpSounds[index];
    await _playSound(selectedLevelUpSound);
  }

  Future<void> _playSound(String assetPath) async {
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

  /// Ensures the TTS engine is configured for the current target language.
  Future<void> _ensureTtsLanguage() async {
    final lang = _languageProvider.ttsLanguageCode;
    if (_lastTtsLanguage == lang) return;
    await _tts.setLanguage(lang);
    _lastTtsLanguage = lang;
  }

  /// Speak arbitrary [text] using TTS in the current target language.
  /// [speed] overrides the current global speed for this utterance.
  Future<void> speak(String text, {double? speed}) async {
    if (text.isEmpty) return;
    await _ensureTtsLanguage();
    await _tts.setSpeechRate(speed ?? _ttsSpeed);
    await _tts.stop();
    await _tts.speak(text);
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
