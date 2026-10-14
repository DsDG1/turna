import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:turna/application/anki_official/render/official_anki_av_coordinator.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/core/ohos_target.dart';
import 'package:turna/service/audio_backend.dart';

/// Production AV/TTS adapter. Never used from tests as a recorder.
///
/// On HarmonyOS there is no `audioplayers` implementation and its constructor
/// reaches for the platform channel immediately, so the file player is the
/// hand-written audio channel (`OhosAudioBackend`) instead — constructing an
/// `AudioPlayer` there fails the whole renderer boot with a
/// `MissingPluginException` before the first card is ever presented.
class OfficialAnkiAvPlayerAdapter implements OfficialAnkiAvPlayer {
  OfficialAnkiAvPlayerAdapter({
    required AudioController audio,
    AudioPlayer? filePlayer,
  })  : _audio = audio,
        _filePlayer = isHarmonyOsTarget ? null : (filePlayer ?? AudioPlayer()),
        _ohosFiles = isHarmonyOsTarget
            ? OhosAudioBackend(slot: AudioSlot.speech)
            : null;

  final AudioController _audio;
  final AudioPlayer? _filePlayer;
  final OhosAudioBackend? _ohosFiles;
  var voiceCapabilityLimited = false;
  var otherArgsCapabilityLimited = false;
  String? lastCapabilityNote;

  @override
  Future<void> playFile(String path) async {
    final ohosFiles = _ohosFiles;
    if (ohosFiles != null) {
      await ohosFiles.playSandboxFile(path);
      return;
    }
    final player = _filePlayer!;
    await player.stop();
    await player.play(DeviceFileSource(path));
    await player.onPlayerComplete.first;
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
    final ohosFiles = _ohosFiles;
    if (ohosFiles != null) {
      await ohosFiles.stopPlayback();
    } else {
      await _filePlayer!.stop();
    }
    await _audio.stopSystemTts();
  }

  @override
  Future<void> dispose() async {
    await stop();
    final ohosFiles = _ohosFiles;
    if (ohosFiles != null) {
      await ohosFiles.releasePlayer();
    } else {
      await _filePlayer!.dispose();
    }
  }
}
