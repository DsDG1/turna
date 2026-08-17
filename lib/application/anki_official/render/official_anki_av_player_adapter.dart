import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:turna/application/anki_official/render/official_anki_av_coordinator.dart';
import 'package:turna/application/audio_controller.dart';

/// Production AV/TTS adapter. Never used from tests as a recorder.
class OfficialAnkiAvPlayerAdapter implements OfficialAnkiAvPlayer {
  OfficialAnkiAvPlayerAdapter({
    required AudioController audio,
    AudioPlayer? filePlayer,
  })  : _audio = audio,
        _filePlayer = filePlayer ?? AudioPlayer();

  final AudioController _audio;
  final AudioPlayer _filePlayer;
  var voiceCapabilityLimited = false;
  var otherArgsCapabilityLimited = false;
  String? lastCapabilityNote;

  @override
  Future<void> playFile(String path) async {
    await _filePlayer.stop();
    await _filePlayer.play(DeviceFileSource(path));
    await _filePlayer.onPlayerComplete.first;
  }

  @override
  Future<bool> speak({
    required String text,
    String? lang,
    List<String> voices = const <String>[],
    double? speed,
    List<String> otherArgs = const <String>[],
  }) async {
    if (voices.isNotEmpty) {
      voiceCapabilityLimited = true;
      lastCapabilityNote = 'voice_unsupported';
    }
    if (otherArgs.isNotEmpty) {
      otherArgsCapabilityLimited = true;
      lastCapabilityNote = 'other_args_unsupported';
    }
    final spoken = text;
    final result = await _audio.speakWithResult(
      spoken,
      speed: speed,
      languageCode: lang,
    );
    return result.source != TtsSpeakSource.failed;
  }

  @override
  Future<void> stop() async {
    await _filePlayer.stop();
    await _audio.stopSystemTts();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _filePlayer.dispose();
  }
}
