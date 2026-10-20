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

// Dart imports:
import 'dart:async';
import 'dart:convert';

// Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

/// The Android / iOS implementation: the same `audioplayers` calls the app has
/// always made, including the playback mode each slot was tuned for.
///
/// [playMode] is a constructor value rather than a branch inside the call: the
/// effects slot has always played through `PlayerMode.lowLatency` (SoundPool),
/// and the platform seam that introduced this class silently dropped it, which
/// turned an answer cue into a `mediaPlayer` load — a regression with no error
/// attached. The speech slot must stay on `mediaPlayer`: a low-latency player
/// cannot take a long or streamed source.
class AudioplayersAudioBackend implements AudioBackend {
  AudioplayersAudioBackend(
    this._player, {
    this.playMode = PlayerMode.mediaPlayer,
  });

  final AudioPlayer _player;
  final PlayerMode playMode;

  @override
  Future<void> playAsset(String assetPath) async {
    await _player.play(AssetSource(assetPath), mode: playMode);
  }

  @override
  Future<void> playFile(String absolutePath) async {
    await _player.play(DeviceFileSource(absolutePath), mode: playMode);
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

  /// Absolute cache path per asset, so the base64 transfer and the file write
  /// happen once instead of on every play.
  final Map<String, String> _staged = <String, String>{};

  /// The asset the startup playback probe uses: the smallest bundled sound, so
  /// the probe costs as little as possible.
  static const String probeAsset = 'sounds/error_1.mp3';

  /// Ceiling on one `playAsset` round trip.
  ///
  /// Without it a native call that never answers is indistinguishable from a
  /// slow one: the Dart future simply never completes, so the caller awaits
  /// forever and neither the success nor the failure line is ever written. That
  /// is not hypothetical — a device run produced a correct plugin, correct
  /// assets, zero errors and no sound, with the log empty at exactly the point
  /// where a hang and a success look the same. A hung platform call has to
  /// become a named failure; silence is the one outcome that teaches nothing.
  static const Duration _playTimeout = Duration(seconds: 10);

  /// Ceiling on one asset-bundle read. Same reasoning as [_playTimeout]: a read
  /// that never completes must be reported, not waited on.
  static const Duration _bundleReadTimeout = Duration(seconds: 10);

  @override
  Future<void> playAsset(String assetPath) async {
    // Staging and playback are two round trips: the asset is written into the
    // app cache once, then played by path. Besides saving the base64 transfer
    // on repeats, it makes each half's outcome land in the Dart log — this
    // plugin's own hilog output never reaches the device log, so a combined
    // call that hangs cannot be attributed to a half.
    final staged = await _stagedPath(assetPath);
    await _channel.invokeMethod<void>('playFile', <String, dynamic>{
      'player': slot.wireName,
      'path': staged,
    }).timeout(_playTimeout,
        onTimeout: () => throw TimeoutException(
              'playFile did not answer within ${_playTimeout.inSeconds}s '
              '(player=${slot.wireName}, staged=$staged)',
            ));
  }

  /// Plays a file that already lives in the app sandbox — not a bundle asset,
  /// so no staging — and answers only when the clip completes, matching what
  /// `audioplayers`' `onPlayerComplete` gives the other platforms.
  ///
  /// Used by the official reviewer's AV path for card audio, whose files are
  /// collection media the resolver has already placed on disk. `awaitCompletion`
  /// is a separate round trip because the plugin's `playFile` reply only means
  /// the clip was accepted.
  Future<void> playSandboxFile(String path) async {
    await _channel.invokeMethod<void>('playFile', <String, dynamic>{
      'player': slot.wireName,
      'path': path,
    }).timeout(_playTimeout,
        onTimeout: () => throw TimeoutException(
              'playFile did not answer within ${_playTimeout.inSeconds}s '
              '(player=${slot.wireName}, path=$path)',
            ));
    await _channel.invokeMethod<void>('awaitCompletion', <String, dynamic>{
      'player': slot.wireName,
    }).timeout(const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException(
              'awaitCompletion did not answer within 10s '
              '(player=${slot.wireName}, path=$path)',
            ));
  }

  /// Stops whatever this slot is playing, if anything.
  Future<void> stopPlayback() async {
    await _channel.invokeMethod<void>('stop', <String, dynamic>{
      'player': slot.wireName,
    }).timeout(_playTimeout,
        onTimeout: () => throw TimeoutException(
              'stop did not answer within ${_playTimeout.inSeconds}s '
              '(player=${slot.wireName})',
            ));
  }

  /// Releases the native player behind this slot; the next play recreates it.
  Future<void> releasePlayer() async {
    await _channel.invokeMethod<void>('release', <String, dynamic>{
      'player': slot.wireName,
    }).timeout(_playTimeout,
        onTimeout: () => throw TimeoutException(
              'release did not answer within ${_playTimeout.inSeconds}s '
              '(player=${slot.wireName})',
            ));
  }

  /// Absolute cache path for [assetPath], staging it on first use.
  Future<String> _stagedPath(String assetPath) async {
    final known = _staged[assetPath];
    if (known != null) return known;
    final bytes = await _readBundleBytes(assetPath);
    if (bytes == null) {
      throw StateError('asset bundle read failed for $assetPath');
    }
    final dest =
        await _channel.invokeMethod<String>('stageBytes', <String, dynamic>{
      'name': assetPath,
      'data': base64Encode(bytes),
    }).timeout(_playTimeout,
            onTimeout: () => throw TimeoutException(
                  'stageBytes did not answer within ${_playTimeout.inSeconds}s '
                  '(path=$assetPath, ${bytes.length} bytes)',
                ));
    if (dest == null || dest.isEmpty) {
      throw StateError('stageBytes returned no path for $assetPath');
    }
    logger.d('Audio: staged $assetPath -> $dest');
    _staged[assetPath] = dest;
    return dest;
  }

  /// Reads [assetPath] out of the Flutter asset bundle, or null when it cannot.
  ///
  /// Under its own timeout for the same reason as the channel calls: a read that
  /// never completes has to be reported, not waited on. The key is the bundle
  /// key, i.e. with the `assets/` prefix the caller strips for the platform.
  Future<Uint8List?> _readBundleBytes(String assetPath) async {
    const bundleKey = 'assets/';
    final key =
        assetPath.startsWith(bundleKey) ? assetPath : '$bundleKey$assetPath';
    try {
      final data = await rootBundle.load(key).timeout(_bundleReadTimeout);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      logger.d('Audio: bundle read ok for $key (${bytes.length} bytes)');
      return bytes;
    } catch (e) {
      logger.w('Audio: bundle read failed for $key: $e');
      return null;
    }
  }

  /// Round-trips a trivial call so a caller can tell "this channel has no
  /// handler" apart from "the handler is slow".
  ///
  /// Needed because this embedding does not answer a channel that has no
  /// handler registered: the Dart future never completes and no exception is
  /// raised, so absence of a reply is the only signal available.
  Future<bool> ping() async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('ping')
          .timeout(const Duration(seconds: 5));
      logger.d('Audio[${slot.wireName}]: ping replied $ok');
      await _reportDiagnostic('audio[${slot.wireName}]: ping replied $ok');
      return ok == true;
    } catch (e) {
      logger.w('Audio[${slot.wireName}]: ping failed: $e');
      await _reportDiagnostic('audio[${slot.wireName}]: ping FAILED: $e');
      return false;
    }
  }

  /// Stages one small asset and plays it, to prove both halves of the path.
  ///
  /// Staging alone was not enough, and the device run that established this is
  /// the reason: the staging half reported success — correct byte count, correct
  /// cache path — while nothing was ever audible, because the half nobody had
  /// measured is the half that decides whether sound comes out. This goes
  /// through [playAsset], i.e. the exact path a real effect takes, rather than a
  /// parallel one that could agree while the real path does not.
  ///
  /// The player and the fd handle are released afterwards so the probe leaves
  /// nothing open for the rest of the session.
  ///
  /// Runs at startup so the answer arrives on the next launch rather than on
  /// the next wrong answer. Failure is reported, never thrown: this is a
  /// diagnostic and startup must not depend on it.
  Future<bool> probePlayback() async {
    try {
      await playAsset(probeAsset);
      logger.d('Audio: playback probe started for $probeAsset');
      // Waiting for `completed` rather than releasing on the play reply: that
      // reply means the player accepted the command, and a probe that releases
      // immediately after it truncates the very clip it is trying to prove —
      // observed on device as `playing` followed by `stopped` 50 ms later.
      final outcome = await _channel
          .invokeMethod<String>('awaitCompletion', <String, dynamic>{
        'player': slot.wireName,
      }).timeout(const Duration(seconds: 12),
              onTimeout: () => throw TimeoutException(
                    'awaitCompletion did not answer within 12s '
                    '(player=${slot.wireName})',
                  ));
      logger.d('Audio: playback probe ok for $probeAsset ($outcome)');
      await _reportDiagnostic('audio probe: $probeAsset $outcome');
      return true;
    } catch (e) {
      logger.w('Audio: playback probe failed for $probeAsset: $e');
      await _reportDiagnostic('audio probe FAILED for $probeAsset: $e');
      return false;
    } finally {
      try {
        await release();
      } catch (e) {
        // Best-effort teardown. The probe leaves a player and an open fd
        // otherwise, and nothing downstream depends on the release landing.
        logger.d('Audio: playback probe release skipped: $e');
      }
    }
  }

  /// Mirrors a Dart-side outcome into the platform log.
  ///
  /// The Dart logger does not reach hilog on this embedding, so a probe outcome
  /// is otherwise only observable as the *absence* of a line — and this log
  /// buffer has already been observed to evict app-domain lines, which makes
  /// absence worthless as evidence. Reporting the outcome positively is the
  /// only way to tell "the probe failed" from "the log lost the line".
  Future<void> _reportDiagnostic(String message) async {
    try {
      await _channel.invokeMethod<void>('reportDiagnostic', <String, dynamic>{
        'message': message,
      }).timeout(const Duration(seconds: 3));
    } catch (e) {
      // Best-effort: the echo is a diagnostic aid, and a failure to deliver it
      // must not change the probe's own result.
    }
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
    // Effects keep the low-latency player the app shipped with: these are
    // 1–2 second cues fired on an answer, where `mediaPlayer` preparation is
    // audible as lag.
    effects: AudioplayersAudioBackend(
      effectsPlayer(),
      playMode: PlayerMode.lowLatency,
    ),
    speech: AudioplayersAudioBackend(speechPlayer()),
  );
}

/// One-shot check that the hand-written audio channel is wired *and audible*.
///
/// Run at startup on the companion build because a channel without a handler is
/// silent there: this embedding does not answer it, so the Dart future never
/// completes and no exception is raised. Without this probe the first symptom of
/// a missing handler is a sound effect that never plays and never reports
/// anything, which is exactly how a day was spent.
///
/// Pinging only proves the handler exists; a device run had a handler that
/// answered, staged the asset byte-for-byte, and still made no sound, because
/// nothing had exercised the playback hop. Hence the play, not just the ping.
Future<void> probeAudioChannel() async {
  if (kIsWeb || !isHarmonyOsTarget) return;
  final backend = OhosAudioBackend(slot: AudioSlot.effects);
  await backend.ping();
  await backend.probePlayback();
}

/// Logs and swallows a playback failure.
///
/// Used by the fire-and-forget paths (a wrong-answer cue, a spoken word), where
/// there is no caller to hand an error to and no fallback worth attempting. The
/// paths that do have a fallback — course-pack media, deck media — let the error
/// propagate so they can try the next source.
///
/// Success is logged too, and that is not decoration. Silence used to cover
/// three indistinguishable states — the gate skipped the call, the call was
/// never made, and the call succeeded but nothing was audible — so a companion
/// build whose whole purpose is to make audio work could not prove it had. The
/// device run that found this had a correct plugin, correct assets, zero
/// failures, and no sound, with nothing in the log to tell those apart.
Future<void> playIgnoringFailure(
  Future<void> Function() play, {
  required String what,
}) async {
  // Logged before the await as well as after. The "before" line is what makes a
  // hang readable: `attempting` with no matching `played`/`failed` is a native
  // call that never answered, whereas silence on both sides means the call was
  // never made. The first device run had neither, which is why a broken port
  // and a working one were indistinguishable.
  logger.d('Audio: attempting $what');
  try {
    await play();
    logger.d('Audio: $what played');
  } catch (e) {
    logger.w('Audio: $what failed: $e');
  }
}
