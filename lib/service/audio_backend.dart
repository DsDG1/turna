// Platform audio backend.
//
// `audioplayers` has no OpenHarmony implementation, and the dependency ratchet
// (ADR 0047 §5.5) forbids overriding it, so the companion build talks to a
// hand-written ArkTS plugin (`AudioPlugin.ets`, AVPlayer) over a MethodChannel.
// Everything above this file — `AudioController` and its many callers — keeps
// one call shape and never learns which side ran.
//
// Two implementations rather than a branch inside each call site: a capability
// that is missing on one platform has to be missing *loudly* at construction
// time, and four call sites each asking "am I on OHOS?" is how the first
// companion build ended up half-wired (see `lib/core/ohos_target.dart`).

// Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

// Project imports:
import 'package:turna/core/logger.dart';
import 'package:turna/core/ohos_target.dart';

/// Which of the two independent players an action applies to.
///
/// The split is not cosmetic: an error cue must not cut off the word being
/// spoken, and a spoken word must not swallow the level-up chime. Keeping them
/// separate is what lets both be audible at once.
enum AudioSlot {
  effects('effects'),
  speech('speech');

  const AudioSlot(this.wireName);

  /// Identifier understood by the native plugin.
  final String wireName;
}

/// Plays a short clip, from a bundled asset or a file in the sandbox.
///
/// Implementations must throw on a source that cannot be played rather than
/// returning quietly: callers decide whether to fall back to a voice, and a
/// silent success removes that decision.
abstract class AudioBackend {
  /// Plays a bundled asset, addressed relative to the asset root — the same
  /// shape `AudioController.normalizeAssetPath` produces, e.g.
  /// `sounds/error_1.mp3`.
  Future<void> playAsset(String assetPath);

  /// Plays a file that already exists in the app sandbox (imported course-pack
  /// media, Anki deck media).
  Future<void> playFile(String absolutePath);

  /// Stops playback in this slot and keeps the backend usable.
  Future<void> stop();

  /// Stops playback and gives up any handle on the current file.
  ///
  /// Separate from [stop] because the media player holds an open handle to
  /// `anki_media` files, which would otherwise keep a deck's media undeletable
  /// on uninstall.
  Future<void> release();
}

/// The Android / iOS implementation, unchanged in behaviour: the same
/// `audioplayers` calls the app has always made.
class AudioplayersAudioBackend implements AudioBackend {
  AudioplayersAudioBackend(this._player);

  final AudioPlayer _player;

  @override
  Future<void> playAsset(String assetPath) async {
    await _player.play(AssetSource(assetPath));
  }

  @override
  Future<void> playFile(String absolutePath) async {
    await _player.play(DeviceFileSource(absolutePath));
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Future<void> release() async {
    await _player.release();
  }
}

/// The OpenHarmony companion build: AVPlayer behind `AudioPlugin.ets`.
class OhosAudioBackend implements AudioBackend {
  OhosAudioBackend({required this.slot, MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'me.dsdogs.turna/audio';

  final MethodChannel _channel;

  /// Which native player this instance drives.
  final AudioSlot slot;

  @override
  Future<void> playAsset(String assetPath) async {
    await _channel.invokeMethod<void>('playAsset', <String, dynamic>{
      'player': slot.wireName,
      'path': assetPath,
    });
  }

  @override
  Future<void> playFile(String absolutePath) async {
    await _channel.invokeMethod<void>('playFile', <String, dynamic>{
      'player': slot.wireName,
      'path': absolutePath,
    });
  }

  @override
  Future<void> stop() async {
    await _channel.invokeMethod<void>('stop', <String, dynamic>{
      'player': slot.wireName,
    });
  }

  @override
  Future<void> release() async {
    await _channel.invokeMethod<void>('release', <String, dynamic>{
      'player': slot.wireName,
    });
  }
}

/// The backend this build should use, for each slot.
///
/// The only place the platform is asked about: everything else receives an
/// [AudioBackend] from DI.
///
/// The players arrive as factories, not instances, and that is load-bearing.
/// `AudioPlayer`'s constructor reaches for its platform channel immediately, so
/// handing one in would raise `MissingPluginException` on a build with no
/// `audioplayers` plugin — thrown from a DI getter, so it escaped as an
/// uncaught framework error instead of degrading anything. Taking a closure lets
/// the OHOS branch never construct one.
({AudioBackend effects, AudioBackend speech}) createAudioBackends({
  required AudioPlayer Function() effectsPlayer,
  required AudioPlayer Function() speechPlayer,
}) {
  if (isHarmonyOsTarget) {
    return (
      effects: OhosAudioBackend(slot: AudioSlot.effects),
      speech: OhosAudioBackend(slot: AudioSlot.speech),
    );
  }
  return (
    effects: AudioplayersAudioBackend(effectsPlayer()),
    speech: AudioplayersAudioBackend(speechPlayer()),
  );
}

/// Logs and swallows a playback failure.
///
/// Used by the fire-and-forget paths (a wrong-answer cue, a spoken word), where
/// there is no caller to hand an error to and no fallback worth attempting. The
/// paths that do have a fallback — course-pack media, deck media — let the error
/// propagate so they can try the next source.
Future<void> playIgnoringFailure(
  Future<void> Function() play, {
  required String what,
}) async {
  try {
    await play();
  } catch (e) {
    logger.w('Audio: $what failed: $e');
  }
}
