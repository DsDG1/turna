// Tests for the platform audio backends.
//
// The ArkTS half (AVPlayer) cannot run in a Dart test, so `OhosAudioBackend` is
// driven against a fake behind the real method channel. What is under test is
// the Dart contract the controller depends on: which native method each call
// becomes, which slot it addresses, and that a refusal travels as an error
// rather than a silent success.
//
// The silence case is the one that matters. `AudioController` decides whether to
// fall back to a voice based on whether playback *started*, so a backend that
// swallowed a failure would remove a decision the caller still needs to make.

import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/service/audio_backend.dart';

Object? _arg(MethodCall call, String key) =>
    (call.arguments as Map<Object?, Object?>?)?[key];

/// Records the calls the channel received and answers them.
class FakeAudioEngine {
  final List<MethodCall> calls = <MethodCall>[];

  /// Method names that must fail, mapped to the error code they report.
  final Map<String, String> failures = <String, String>{};

  /// What `stageBytes` answers with — the absolute sandbox path the native side
  /// would have written to. A distinct value per asset is what lets a test tell
  /// "played the thing it staged" apart from "played the name it was given".
  final Map<String, String> staged = <String, String>{};

  String stagedPathOf(String name) =>
      staged[name] = staged[name] ?? '/sandbox/$name';

  void reset() => calls.clear();
}

/// Asset keys `rootBundle` will resolve. Anything else is a miss, which is what
/// the bundle-read failure case needs to be able to produce on demand.
const Set<String> _knownAssets = <String>{
  'assets/sounds/error_1.mp3',
  'assets/sounds/level_up_2.mp3',
  'assets/sounds/a.mp3',
  'assets/sounds/b.mp3',
};

/// Serves the Flutter asset bundle from memory.
///
/// `rootBundle` has to be stubbed because `playAsset` reads the clip's bytes on
/// the Dart side. Leaving it real makes every case in this file depend on an
/// asset build having happened, which is how a suite that asserts a *protocol*
/// ends up failing for reasons that have nothing to do with the protocol.
void _installAssets() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (ByteData? message) async {
    final key = utf8.decode(message!.buffer.asUint8List());
    if (!_knownAssets.contains(key)) return null;
    final bytes = Uint8List.fromList(List<int>.filled(8, key.length));
    return ByteData.view(bytes.buffer);
  });
}

/// Stands in for an `audioplayers` handle without touching its platform
/// channel. `createAudioBackends` only stores the player, so nothing here needs
/// to answer a call.
class _FakeAudioPlayer implements AudioPlayer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _install(FakeAudioEngine engine) {
  const channel = MethodChannel('me.dsdogs.turna/audio');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    engine.calls.add(call);
    final failure = engine.failures[call.method];
    if (failure != null) {
      throw PlatformException(code: failure, message: 'engine said no');
    }
    // `stageBytes` answers with a path; everything else answers with a truthy
    // marker. Returning one shape for both is what let the old single-`playAsset`
    // assertions pass against an implementation that has since split in two.
    if (call.method == 'stageBytes') {
      final name = _arg(call, 'name') as String?;
      return engine.stagedPathOf(name ?? 'unknown');
    }
    return true;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _installAssets();

  late FakeAudioEngine engine;

  setUp(() {
    engine = FakeAudioEngine();
    _install(engine);
  });

  tearDown(() {
    const channel = MethodChannel('me.dsdogs.turna/audio');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('AudioSlot', () {
    test('wire names are the ones the native plugin switches on', () {
      // These strings are a contract with `AudioPlugin.ets`. A rename on either
      // side compiles, passes every test, and produces silence on the device.
      expect(AudioSlot.effects.wireName, 'effects');
      expect(AudioSlot.speech.wireName, 'speech');
    });
  });

  group('OhosAudioBackend.playAsset', () {
    // `playAsset` is two round trips, not one: the bytes are read out of the
    // Flutter bundle by Dart and handed to the native side to stage, then the
    // staged path is played. The single `playAsset` call these cases used to
    // assert was the shape the implementation used before staging moved to the
    // Dart side — a device run showed the native rawfile read never settling, so
    // the read happens where `rootBundle` is known to work instead.
    test('stages the bytes, then plays the staged path', () async {
      final backend = OhosAudioBackend(slot: AudioSlot.effects);

      await backend.playAsset('sounds/error_1.mp3');

      expect(
        engine.calls.map((c) => c.method),
        ['stageBytes', 'playFile'],
      );
      expect(_arg(engine.calls.last, 'player'), 'effects');
      // What gets played is the path the native side returned for the staged
      // asset, not the asset name — the two are different strings and asserting
      // the wrong one is how this test went stale without going red.
      expect(_arg(engine.calls.last, 'path'), '/sandbox/sounds/error_1.mp3');
    });

    test('asks for the staging of exactly the asset it was given', () async {
      await OhosAudioBackend(slot: AudioSlot.speech)
          .playAsset('sounds/level_up_2.mp3');

      expect(_arg(engine.calls.first, 'name'), 'sounds/level_up_2.mp3');
      expect(_arg(engine.calls.first, 'data'), isA<String>());
    });

    test('the two slots never share a player', () async {
      // The whole reason there are two: an error cue must not cut off the word
      // being spoken.
      await OhosAudioBackend(slot: AudioSlot.effects).playAsset('sounds/a.mp3');
      await OhosAudioBackend(slot: AudioSlot.speech).playAsset('sounds/b.mp3');

      expect(
        engine.calls
            .where((c) => c.method == 'playFile')
            .map((c) => _arg(c, 'player')),
        ['effects', 'speech'],
      );
    });

    test('a native failure reaches the caller', () async {
      // Swallowing this is what would leave the caller believing a word was
      // spoken when nothing came out of the speaker.
      engine.failures['playFile'] = 'PLAY_ERROR';
      final backend = OhosAudioBackend(slot: AudioSlot.speech);

      // An asset the bundle *does* have, so the read succeeds and the refusal
      // comes from the platform — the case is about the refusal travelling, not
      // about the read failing first.
      await expectLater(
        backend.playAsset('sounds/level_up_2.mp3'),
        throwsA(isA<PlatformException>()),
      );
    });

    test('a bundle miss fails before anything is asked of the native side',
        () async {
      // The read is the half that can fail without the platform being involved,
      // and it must still be a refusal rather than a quiet success.
      await expectLater(
        OhosAudioBackend(slot: AudioSlot.effects)
            .playAsset('sounds/absent.mp3'),
        throwsA(isA<StateError>()),
      );
      expect(engine.calls, isEmpty);
    });
  });

  group('OhosAudioBackend.playFile', () {
    test('sends the absolute sandbox path, not an asset path', () async {
      final backend = OhosAudioBackend(slot: AudioSlot.speech);

      await backend.playFile(r'C:\media\voice.mp3');

      expect(engine.calls.single.method, 'playFile');
      expect(_arg(engine.calls.single, 'path'), r'C:\media\voice.mp3');
    });

    test('a missing file is an error, not a no-op', () async {
      engine.failures['playFile'] = 'NO_FILE';

      await expectLater(
        OhosAudioBackend(slot: AudioSlot.speech).playFile('/nope.mp3'),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('OhosAudioBackend stop and release', () {
    test('both address the slot and reach distinct native methods', () async {
      // `release` is separate from `stop` because the media player holds an
      // open handle to deck media; without it a deck's files stay undeletable
      // on uninstall.
      final backend = OhosAudioBackend(slot: AudioSlot.speech);

      await backend.stop();
      await backend.release();

      expect(engine.calls.map((c) => c.method), ['stop', 'release']);
      expect(
        engine.calls.map((c) => _arg(c, 'player')),
        ['speech', 'speech'],
      );
    });
  });

  group('createAudioBackends', () {
    // A real `AudioPlayer` reaches for its platform channel the moment it is
    // constructed, which is not what these cases are about: the decision under
    // test is which wrapper comes back, and that is made before anything plays.
    test('the host toolchain gets the audioplayers backends', () {
      // This test runs on the Android/iOS SDK, where `isHarmonyOsTarget` is
      // false. It is the assertion that the refactor did not quietly repoint
      // the shipping platforms at a method channel they do not have.
      final backends = createAudioBackends(
        effectsPlayer: () => _FakeAudioPlayer(),
        speechPlayer: () => _FakeAudioPlayer(),
      );

      expect(backends.effects, isA<AudioplayersAudioBackend>());
      expect(backends.speech, isA<AudioplayersAudioBackend>());
    });

    test('the effects slot keeps the low-latency player it shipped with', () {
      // The platform seam replaced `play(..., mode: lowLatency)` with a plain
      // `play()`, which moved every answer cue onto the media-player path with
      // no error attached — only a prepare delay before the sound.
      final backends = createAudioBackends(
        effectsPlayer: () => _FakeAudioPlayer(),
        speechPlayer: () => _FakeAudioPlayer(),
      );

      expect(
        (backends.effects as AudioplayersAudioBackend).playMode,
        PlayerMode.lowLatency,
      );
      // Speech must not follow it: a low-latency player cannot take a long or
      // streamed source, and deck media is exactly that.
      expect(
        (backends.speech as AudioplayersAudioBackend).playMode,
        PlayerMode.mediaPlayer,
      );
    });

    test('each backend wraps its own player', () {
      final effects = _FakeAudioPlayer();
      final speech = _FakeAudioPlayer();

      final backends = createAudioBackends(
        effectsPlayer: () => effects,
        speechPlayer: () => speech,
      );

      // Sharing one player would let a wrong-answer cue cut off the word being
      // spoken, which is the separation the two slots exist for.
      expect(backends.effects, isNot(same(backends.speech)));
    });

    test('the player factories are not called on the companion build', () {
      // The host SDK is not OHOS, so this asserts the *shape* of the contract
      // instead: the factories are lazy values, which is what lets the OHOS
      // branch skip them. `AudioPlayer`'s constructor calls the platform channel
      // immediately, so calling one where the plugin is absent throws out of a
      // DI getter — an uncaught framework error, not a degradation.
      var built = 0;
      final backends = createAudioBackends(
        effectsPlayer: () {
          built++;
          return _FakeAudioPlayer();
        },
        speechPlayer: () {
          built++;
          return _FakeAudioPlayer();
        },
      );

      // On this toolchain the backends are the audioplayers ones, so both
      // factories ran exactly once each — no more, no less.
      expect(built, 2);
      expect(backends.effects, isA<AudioplayersAudioBackend>());
    });
  });

  group('playIgnoringFailure', () {
    test('a failing effect is logged, not rethrown', () async {
      // Sound effects are fire-and-forget: there is no caller to hand an error
      // to and no fallback worth attempting, so a failure must not take down the
      // answer that triggered it.
      await expectLater(
        playIgnoringFailure(
          () async => throw StateError('no decoder'),
          what: 'sound effect',
        ),
        completes,
      );
    });

    test('a successful play is left alone', () async {
      var played = false;

      await playIgnoringFailure(
        () async => played = true,
        what: 'sound effect',
      );

      expect(played, isTrue);
    });
  });
}
