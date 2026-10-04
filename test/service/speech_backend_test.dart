// Tests for the platform speech backends.
//
// `OhosSpeechBackend` is driven against a fake CoreSpeechKit behind the real
// method channel; what is under test is the Dart contract the controller and the
// availability checker depend on — which native method each call becomes, what
// the rate conversion produces, and how a platform refusal is reported.
//
// The cases that matter most are the degraded ones. On the companion build a
// device may have no voice for the course language at all, and the engine may
// have to fall back to a different one; both must be visible to the caller
// rather than turning into silence.

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/service/speech_backend.dart';

Object? _arg(MethodCall call, String key) =>
    (call.arguments as Map<Object?, Object?>?)?[key];

/// Records the calls the channel received and answers them.
class FakeTtsEngine {
  /// Answer to the next `init`, or null for a plain success.
  Map<String, Object?>? initReply;

  /// When true, `init` reports that the requested language was refused and a
  /// fallback voice was used instead.
  bool initDegraded = false;

  /// When true, `init` fails outright.
  bool initFails = false;

  /// Voices the platform can already speak, as `{language, person}` entries.
  List<Object> installedVoices = <Object>[];

  /// Voices the platform says it could provide if asked, same entry shape.
  ///
  /// Separate from [installedVoices] because the two answers drive different
  /// replies to the user: "this device has no Turkish voice" and "Turkish is
  /// downloadable" are not the same situation.
  List<Object> supportedVoices = <Object>[];

  /// Replaces the whole reply when set, for shapes the two lists above cannot
  /// express (a key the platform left out, say).
  Object? voicesReplyOverride;

  /// When true, `speak` reports a refusal.
  bool speakFails = false;

  final List<MethodCall> calls = <MethodCall>[];

  int voiceQueries = 0;
}

FakeTtsEngine? _engine;

void _install(FakeTtsEngine engine) {
  _engine = engine;
  const channel = MethodChannel('me.dsdogs.turna/tts');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    final e = _engine!;
    e.calls.add(call);
    switch (call.method) {
      case 'init':
        if (e.initFails) {
          throw PlatformException(code: 'TTS_INIT_FAILED');
        }
        if (e.initDegraded) {
          return <String, Object?>{
            'language': 'en-US',
            'requested': 'tr-TR',
            'degraded': true,
          };
        }
        return e.initReply ??
            <String, Object?>{'language': _arg(call, 'language')};
      case 'voices':
        e.voiceQueries++;
        // Two keyed lists, matching the ArkTS reply. Which module each came
        // from (`online` 0 / 1) is decided inside the plugin, so nothing about
        // it is observable from Dart — see the guard test in
        // `ohos_eol_architecture_guard_test.dart` that pins the plugin side.
        return e.voicesReplyOverride ??
            <String, Object?>{
              'installed': e.installedVoices,
              'supported': e.supportedVoices,
            };
      case 'speak':
        if (e.speakFails) {
          throw PlatformException(code: 'TTS_SPEAK_FAILED');
        }
        return true;
      case 'stop':
      case 'shutdown':
        return null;
      default:
        return null;
    }
  });
}

class _FakeFlutterTts implements FlutterTts {
  _FakeFlutterTts({this.languageResult, this.speakResult});

  Object? languageResult;
  Object? speakResult;

  final List<String> calls = <String>[];

  @override
  Future<dynamic> setLanguage(String language) async {
    calls.add('setLanguage:$language');
    return languageResult;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    calls.add('setSpeechRate:$rate');
    return 1;
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    calls.add('speak:$text');
    return speakResult;
  }

  @override
  Future<dynamic> stop() async {
    calls.add('stop');
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeTtsEngine engine;

  setUp(() {
    engine = FakeTtsEngine();
    _install(engine);
  });

  tearDown(() {
    const channel = MethodChannel('me.dsdogs.turna/tts');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    _engine = null;
  });

  group('OhosSpeechBackend.init', () {
    test('asks for the requested language and remembers what it got',
        () async {
      final backend = OhosSpeechBackend();

      await backend.init(language: 'tr-TR');

      expect(engine.calls.single.method, 'init');
      expect(_arg(engine.calls.single, 'language'), 'tr-TR');
    });

    test('a fallback voice is adopted rather than the requested one', () async {
      // The engine was created with en-US because tr-TR is not installed. The
      // backend must speak with what it got, or every utterance is silent.
      engine.initDegraded = true;
      final backend = OhosSpeechBackend();

      await backend.init(language: 'tr-TR');
      await backend.bindLanguage('tr-TR');
      await backend.speak('merhaba');

      final speak = engine.calls.last;
      expect(speak.method, 'speak');
      expect(_arg(speak, 'language'), 'tr-TR');
    });

    test('a failed init is reported, not swallowed', () async {
      engine.initFails = true;

      await expectLater(
        OhosSpeechBackend().init(language: 'tr-TR'),
        throwsA(isA<PlatformException>()),
      );
    });

    test('the engine is only brought up once', () async {
      final backend = OhosSpeechBackend();

      await backend.init(language: 'tr');
      await backend.init(language: 'en-US');

      expect(engine.calls.where((c) => c.method == 'init'), hasLength(1));
    });
  });

  group('OhosSpeechBackend.availableLanguages', () {
    test('unpacks the installed voice list into language tags', () async {
      engine.installedVoices = <Object>[
        <String, Object>{'language': 'zh-CN', 'person': 0},
        <String, Object>{'language': 'en-US', 'person': 1},
      ];
      final backend = OhosSpeechBackend();

      expect(await backend.availableLanguages(), ['zh-CN', 'en-US']);
    });

    test('a downloadable voice is supported but not yet available', () async {
      // The distinction the whole two-list split exists for. Turkish is
      // absent from both lists on the verified device, so both answers are
      // empty there — but the moment a device *can* fetch one, this is the
      // shape that has to keep them apart.
      engine.installedVoices = <Object>[
        <String, Object>{'language': 'zh-CN', 'person': 0},
      ];
      engine.supportedVoices = <Object>[
        <String, Object>{'language': 'zh-CN', 'person': 0},
        <String, Object>{'language': 'tr-TR', 'person': 0},
      ];
      final backend = OhosSpeechBackend();

      expect(await backend.availableLanguages(), ['zh-CN']);
      expect(
        await backend.supportedLanguages(),
        containsAll(<String>['zh-CN', 'tr-TR']),
      );
    });

    test('installed voices count as supported even if the plugin omits them',
        () async {
      // A platform whose supported query answers with an empty list would
      // otherwise look like it supports no language at all.
      engine.installedVoices = <Object>[
        <String, Object>{'language': 'en-US', 'person': 0},
      ];
      final backend = OhosSpeechBackend();

      expect(await backend.supportedLanguages(), ['en-US']);
    });

    test('the voice list is cached', () async {
      // `TtsAvailabilityChecker` resolves a locale per utterance; re-asking the
      // engine every time would put a platform round trip on the speak path.
      engine.installedVoices = <Object>[
        <String, Object>{'language': 'en-US', 'person': 0},
      ];
      final backend = OhosSpeechBackend();

      await backend.availableLanguages();
      await backend.supportedLanguages();
      await backend.availableLanguages();

      expect(
        engine.voiceQueries,
        1,
        reason: 'available and supported share one platform round trip',
      );
    });

    test('malformed entries are dropped rather than crashing the list', () async {
      engine.installedVoices = <Object>[
        'not a voice',
        <String, Object>{'person': 0},
        <String, Object>{'language': 'en-US', 'person': 0},
      ];

      expect(await OhosSpeechBackend().availableLanguages(), ['en-US']);
    });

    test('a reply missing the supported key falls back to what is installed',
        () async {
      // A platform build that only answers the installed query must not look
      // like it supports nothing — hence the merge. Pinned because the key
      // names live in two files (ArkTS reply, Dart read) that no host test can
      // execute together; the guard test compares them by source.
      engine.voicesReplyOverride = <String, Object?>{
        'installed': <Object>[
          <String, Object>{'language': 'en-US', 'person': 0},
        ],
      };
      final backend = OhosSpeechBackend();

      expect(await backend.availableLanguages(), ['en-US']);
      expect(await backend.supportedLanguages(), ['en-US']);
    });

    test('an empty reply reads as no voices', () async {
      // The engine started but reported nothing: the UI must render "无" from
      // this rather than hanging on a spinner or claiming a voice exists.
      final backend = OhosSpeechBackend();

      expect(await backend.availableLanguages(), isEmpty);
      expect(await backend.supportedLanguages(), isEmpty);
    });
  });

  group('OhosSpeechBackend rate conversion', () {
    test('the app default speed maps to the engine default', () {
      // flutter_tts documents 0.5 as normal, and the app's own default speed is
      // 1.0 — which arrives here as 0.5.
      expect(OhosSpeechBackend.mapFlutterTtsRateToPercent(0.5), 50);
    });

    test('the slider spans the full percentage range, monotonically', () {
      // Mapping only up to the engine default would make everything above 1.0x
      // sound identical, which is the bug the two anchors exist to prevent.
      expect(OhosSpeechBackend.mapFlutterTtsRateToPercent(0.25), lessThan(50));
      expect(OhosSpeechBackend.mapFlutterTtsRateToPercent(1.0), 100);
    });

    test('out-of-range input is clamped, never wrapped', () {
      expect(OhosSpeechBackend.mapFlutterTtsRateToPercent(-5), 0);
      expect(OhosSpeechBackend.mapFlutterTtsRateToPercent(99), 100);
    });

    test('speak carries the converted rate, not the raw one', () async {
      final backend = OhosSpeechBackend();
      await backend.init(language: 'en-US');
      await backend.bindLanguage('en-US');
      await backend.setRate(1.0);

      await backend.speak('hello');

      final speak = engine.calls.last;
      expect(_arg(speak, 'rate'), 100);
      expect(_arg(speak, 'text'), 'hello');
    });
  });

  group('OhosSpeechBackend.speak', () {
    test('reports the platform refusal as an error', () async {
      engine.speakFails = true;
      final backend = OhosSpeechBackend();
      await backend.init(language: 'en-US');

      await expectLater(
        backend.speak('hello'),
        throwsA(isA<PlatformException>()),
      );
    });

    test('an accepted request reports true', () async {
      final backend = OhosSpeechBackend();
      await backend.init(language: 'en-US');

      expect(await backend.speak('hello'), isTrue);
    });
  });

  group('FlutterTtsSpeechBackend', () {
    test('passes the rate straight through to the plugin', () async {
      // The Android mapping is the plugin's own contract and must not be
      // "helpfully" re-scaled.
      final tts = _FakeFlutterTts();
      final backend = FlutterTtsSpeechBackend(tts);

      await backend.setRate(0.75);

      expect(tts.calls, ['setSpeechRate:0.75']);
    });

    test('normalises the plugin\'s several success shapes to true', () async {
      for (final result in <Object?>[1, true, null]) {
        final backend = FlutterTtsSpeechBackend(_FakeFlutterTts(speakResult: result));
        expect(await backend.speak('hi'), isTrue, reason: '$result');
      }
    });

    test('a zero or false result is a refusal', () async {
      expect(
        await FlutterTtsSpeechBackend(_FakeFlutterTts(speakResult: 0)).speak('hi'),
        isFalse,
      );
      expect(
        await FlutterTtsSpeechBackend(_FakeFlutterTts(speakResult: false))
            .speak('hi'),
        isFalse,
      );
    });

    test('a rejected language binding is reported as false', () async {
      final backend =
          FlutterTtsSpeechBackend(_FakeFlutterTts(languageResult: 0));

      expect(await backend.bindLanguage('tr'), isFalse);
    });

    test('reports no voice list rather than pretending to know one', () async {
      // `flutter_tts` has no "list every voice" call. Returning an empty list
      // keeps callers on their existing per-tag probe path.
      expect(await FlutterTtsSpeechBackend(_FakeFlutterTts()).availableLanguages(),
          isEmpty);
    });
  });

  group('createSpeechBackend', () {
    test('the host toolchain keeps flutter_tts', () {
      // Runs on the Android/iOS SDK. If this ever returns the channel backend,
      // the shipping platforms would talk to a method channel they do not have.
      expect(
        createSpeechBackend(tts: FlutterTts()),
        isA<FlutterTtsSpeechBackend>(),
      );
    });
  });
}
