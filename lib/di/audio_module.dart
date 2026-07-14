// Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:injectable/injectable.dart';

/// Provides the two [AudioPlayer] instances required by [AudioController].
///
/// One player is used for short sound effects (error/level-up), the other for
/// speech/audio assets. Keeping them separate prevents effect playback from
/// interrupting ongoing speech and vice-versa.
@module
abstract class AudioModule {
  @lazySingleton
  @Named('audioPlayer')
  AudioPlayer get audioPlayer => AudioPlayer();

  @lazySingleton
  @Named('speechPlayer')
  AudioPlayer get speechPlayer => AudioPlayer();
}
