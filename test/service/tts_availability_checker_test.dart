import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/service/tts_availability_checker.dart';

class _FakeFlutterTts implements FlutterTts {
  _FakeFlutterTts({
    this.engines = const [],
    this.availableLanguages = const {'sw'},
    this.installedLanguages = const {},
    this.engineShouldFail = false,
    /// Languages only available after Google engine is selected.
    this.googleOnlyLanguages = const {},
    this.googleOnlyInstalled = const {},
  });

  final List<dynamic> engines;
  final Set<String> availableLanguages;
  final Set<String> installedLanguages;
  final bool engineShouldFail;
  final Set<String> googleOnlyLanguages;
  final Set<String> googleOnlyInstalled;

  String? lastEngine;
  final List<String> languageQueries = [];
  final List<String> installedQueries = [];
  final List<String> engineCalls = [];
  int setEngineInFlight = 0;
  int maxSetEngineInFlight = 0;

  /// Artificial delay so concurrent configureSystemEngine calls overlap.
  Duration setEngineDelay = Duration.zero;

  @override
  Future<dynamic> get getEngines async => engines;

  @override
  Future<dynamic> isLanguageAvailable(String language) async {
    languageQueries.add(language);
    if (lastEngine == 'com.google.android.tts' &&
        googleOnlyLanguages.contains(language)) {
      return 1;
    }
    return availableLanguages.contains(language) ? 1 : 0;
  }

  @override
  Future<dynamic> isLanguageInstalled(String language) async {
    installedQueries.add(language);
    if (lastEngine == 'com.google.android.tts' &&
        googleOnlyInstalled.contains(language)) {
      return true;
    }
    return installedLanguages.contains(language);
  }

  @override
  Future<dynamic> setEngine(String engine) async {
    setEngineInFlight++;
    if (setEngineInFlight > maxSetEngineInFlight) {
      maxSetEngineInFlight = setEngineInFlight;
    }
    engineCalls.add(engine);
    try {
      if (setEngineDelay > Duration.zero) {
        await Future<void>.delayed(setEngineDelay);
      }
      if (engineShouldFail) throw Exception('engine failure');
      lastEngine = engine;
      return null;
    } finally {
      setEngineInFlight--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('TtsAvailabilityChecker', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('language available -> reports system TTS available', () async {
      final checker = TtsAvailabilityChecker(
        _FakeFlutterTts(availableLanguages: const {'sw'}),
      );

      expect(await checker.isSystemTtsAvailable('sw'), isTrue);
    });

    test('language unavailable -> reports system TTS unavailable', () async {
      final checker = TtsAvailabilityChecker(
        _FakeFlutterTts(availableLanguages: const {}),
      );

      expect(await checker.isSystemTtsAvailable('sw'), isFalse);
    });

    test('availability query exception -> reports unavailable', () async {
      final throwingTts = _ThrowingFlutterTts();
      final checker = TtsAvailabilityChecker(throwingTts);

      expect(await checker.isSystemTtsAvailable('sw'), isFalse);
    });

    test('resolveLanguageCode returns first available candidate', () async {
      final tts = _FakeFlutterTts(availableLanguages: const {'sw-KE'});
      final checker = TtsAvailabilityChecker(tts);

      expect(await checker.resolveLanguageCode('sw'), 'sw-KE');
      expect(tts.languageQueries, contains('sw'));
      expect(tts.languageQueries, contains('sw-KE'));
    });

    test('languageCandidates includes sw region tags', () {
      final candidates = TtsAvailabilityChecker.languageCandidates('sw');
      expect(candidates, containsAll(['sw', 'sw-KE', 'sw-TZ', 'sw_KE', 'sw_TZ']));
    });

    group('on Android', () {
      setUp(() {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
      });

      tearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });

      test('configureSystemEngine selects Google engine when present', () async {
        final tts = _FakeFlutterTts(
          engines: const [
            {'name': 'com.google.android.tts', 'label': 'Google'},
            {'name': 'com.samsung.SMT', 'label': 'Samsung'},
          ],
        );
        final checker = TtsAvailabilityChecker(tts);

        await checker.configureSystemEngine();

        expect(tts.lastEngine, 'com.google.android.tts');
        expect(checker.isEngineConfigured, isTrue);
      });

      test('configureSystemEngine does nothing when Google engine is absent',
          () async {
        final tts = _FakeFlutterTts(engines: const ['com.samsung.SMT']);
        final checker = TtsAvailabilityChecker(tts);

        await checker.configureSystemEngine();

        expect(tts.lastEngine, isNull);
        expect(checker.isEngineConfigured, isTrue);
      });

      test('configureSystemEngine swallows engine errors', () async {
        final tts = _FakeFlutterTts(
          engines: const ['com.google.android.tts'],
          engineShouldFail: true,
        );
        final checker = TtsAvailabilityChecker(tts);

        await expectLater(
          checker.configureSystemEngine(),
          completes,
        );
      });

      test('isSystemTtsAvailable requires at least one engine', () async {
        final tts = _FakeFlutterTts(
          availableLanguages: const {'sw'},
          engines: const [],
        );
        final checker = TtsAvailabilityChecker(tts);

        expect(await checker.isSystemTtsAvailable('sw'), isFalse);
      });

      test(
        'selects Google engine before language check so OEM default without sw still works',
        () async {
          // Default engine has no Swahili; only Google does.
          final tts = _FakeFlutterTts(
            engines: const [
              'com.samsung.SMT',
              'com.google.android.tts',
            ],
            availableLanguages: const {},
            googleOnlyLanguages: const {'sw', 'sw-KE'},
            googleOnlyInstalled: const {'sw', 'sw-KE'},
          );
          final checker = TtsAvailabilityChecker(tts);

          expect(await checker.isSystemTtsAvailable('sw'), isTrue);
          expect(tts.lastEngine, 'com.google.android.tts');
          // Engine must be set before (or as part of) language resolution.
          expect(tts.languageQueries, isNotEmpty);
        },
      );

      test('configureSystemEngine is idempotent unless force is true', () async {
        final tts = _FakeFlutterTts(
          engines: const ['com.google.android.tts'],
        );
        final checker = TtsAvailabilityChecker(tts);

        await checker.configureSystemEngine();
        tts.lastEngine = null;
        await checker.configureSystemEngine();
        expect(tts.lastEngine, isNull);

        await checker.configureSystemEngine(force: true);
        expect(tts.lastEngine, 'com.google.android.tts');
      });

      test(
        'concurrent configureSystemEngine calls only setEngine once',
        () async {
          final tts = _FakeFlutterTts(
            engines: const ['com.google.android.tts'],
          )..setEngineDelay = const Duration(milliseconds: 40);
          final checker = TtsAvailabilityChecker(tts);

          // Mimic main.dart post-frame + Splash isPreferred racing on startup.
          await Future.wait([
            checker.configureSystemEngine(),
            checker.configureSystemEngine(),
            checker.resolveLanguageCode('sw'),
          ]);

          expect(tts.engineCalls, ['com.google.android.tts']);
          expect(tts.maxSetEngineInFlight, 1);
          expect(checker.isEngineConfigured, isTrue);
        },
      );

      test(
        'vivo-only engine: any system may be available but preferred is not',
        () async {
          final tts = _FakeFlutterTts(
            engines: const ['com.vivo.aiservice'],
            availableLanguages: const {'sw'},
            installedLanguages: const {'sw'},
          );
          final checker = TtsAvailabilityChecker(tts);

          expect(await checker.hasGoogleTtsEngine(), isFalse);
          expect(await checker.listEngineNames(), ['com.vivo.aiservice']);
          // OEM can still claim Swahili — not learning-quality preferred path.
          expect(await checker.isSystemTtsAvailable('sw'), isTrue);
          expect(await checker.isPreferredSystemTtsAvailable('sw'), isFalse);
        },
      );

      test(
        'preferred system TTS requires Google engine and installed locale',
        () async {
          final tts = _FakeFlutterTts(
            engines: const ['com.google.android.tts'],
            availableLanguages: const {'sw-KE'},
            installedLanguages: const {'sw-KE'},
          );
          final checker = TtsAvailabilityChecker(tts);

          expect(await checker.hasGoogleTtsEngine(), isTrue);
          expect(await checker.isPreferredSystemTtsAvailable('sw'), isTrue);
          expect(tts.lastEngine, 'com.google.android.tts');
        },
      );

      test(
        'Google installed but no Swahili pack -> preferred unavailable',
        () async {
          final tts = _FakeFlutterTts(
            engines: const ['com.google.android.tts'],
            availableLanguages: const {},
          );
          final checker = TtsAvailabilityChecker(tts);

          expect(await checker.hasGoogleTtsEngine(), isTrue);
          expect(await checker.isPreferredSystemTtsAvailable('sw'), isFalse);
        },
      );

      test(
        'Google available but voice data not installed -> preferred unavailable',
        () async {
          final tts = _FakeFlutterTts(
            engines: const ['com.google.android.tts'],
            availableLanguages: const {'sw-KE'},
            installedLanguages: const {}, // advertised but not downloaded
          );
          final checker = TtsAvailabilityChecker(tts);

          expect(await checker.isPreferredSystemTtsAvailable('sw'), isFalse);
          final diag = await checker.diagnose('sw');
          expect(diag.preferredStatus, TtsPreferredStatus.swahiliDataMissing);
          expect(diag.hasGoogleEngine, isTrue);
        },
      );

      test(
        'resolveLanguageCode prefers installed locale over merely available',
        () async {
          final tts = _FakeFlutterTts(
            engines: const ['com.google.android.tts'],
            availableLanguages: const {'sw', 'sw-KE'},
            installedLanguages: const {'sw-KE'},
          );
          final checker = TtsAvailabilityChecker(tts);

          // 'sw' is checked first; not installed → continue to sw-KE.
          expect(await checker.resolveLanguageCode('sw'), 'sw-KE');
        },
      );

      test('diagnose reports googleMissing when engines empty', () async {
        final tts = _FakeFlutterTts(
          engines: const [],
          availableLanguages: const {},
        );
        final checker = TtsAvailabilityChecker(tts);
        final diag = await checker.diagnose('sw');
        expect(diag.hasGoogleEngine, isFalse);
        expect(diag.preferredStatus, TtsPreferredStatus.googleMissing);
      });
    });
  });
}

class _ThrowingFlutterTts implements FlutterTts {
  @override
  Future<dynamic> isLanguageAvailable(String language) async =>
      throw Exception('query failed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
