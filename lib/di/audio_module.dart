// Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/service/audio_backend.dart';
import 'package:turna/service/speech_backend.dart';

/// Provides the two independent [AudioBackend] instances and the single
/// [SpeechBackend] required by `AudioController` and `TtsAvailabilityChecker`.
///
/// Two audio players, one per concern: a sound effect must not cut off the word
/// being spoken, and speech must not swallow the level-up chime.
///
/// The `audioplayers` handles are passed as factories and stay unconstructed on
/// the OpenHarmony companion build, where the plugin does not exist: its
/// constructor calls the platform channel immediately, so building one eagerly
/// raised `MissingPluginException` out of a DI getter — an uncaught framework
/// error rather than a degradation.
///
/// [speechBackend] is a single shared instance on purpose. It carries the bound
/// locale and rate, so two instances would mean the one that checks availability
/// and the one that speaks could disagree about which voice is in use.
@module
abstract class AudioModule {
  @lazySingleton
  @Named('audioPlayer')
  AudioPlayer get audioPlayer => AudioPlayer();

  @lazySingleton
  @Named('speechPlayer')
  AudioPlayer get speechPlayer => AudioPlayer();

  @lazySingleton
  @Named('effectsAudio')
  AudioBackend get effectsAudio => createAudioBackends(
        effectsPlayer: () => audioPlayer,
        speechPlayer: () => speechPlayer,
      ).effects;

  @lazySingleton
  @Named('speechAudio')
  AudioBackend get speechAudio => createAudioBackends(
        effectsPlayer: () => audioPlayer,
        speechPlayer: () => speechPlayer,
      ).speech;

  @lazySingleton
  SpeechBackend speechBackend(
    FlutterTts tts,
    // The companion build's engine synthesises a file and the audio backend plays
    // it, so the two are wired together here. Injecting the registered
    // `speechAudio` rather than building a second one matters: two speech
    // players would let one stop the other mid-utterance.
    @Named('speechAudio') AudioBackend speech,
  ) =>
      createSpeechBackend(tts: tts, speaker: speech);
}
