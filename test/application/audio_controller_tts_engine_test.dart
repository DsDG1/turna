import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/core/enums.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/audio/vocab_audio_resolver.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/service/piper_swahili_tts.dart';
import 'package:varnamala/service/tts_availability_checker.dart';

class _PassthroughVocabResolver implements VocabAudioResolver {
  @override
  ResolvedVocabAudio resolve(String wordId) =>
      ResolvedVocabAudio(speakText: wordId);
}

class _FakeFlutterTts implements FlutterTts {
  _FakeFlutterTts({
    this.speakShouldThrow = false,
    this.setLanguageSucceeds = true,
  });

  final bool speakShouldThrow;
  final bool setLanguageSucceeds;

  final List<String> speakCalls = [];
  final List<String> languageCalls = [];
  final List<double> rateCalls = [];
  final List<String> engineCalls = [];
  int stopCalls = 0;

  @override
  Future<dynamic> setLanguage(String language) async {
    languageCalls.add(language);
    return setLanguageSucceeds ? 1 : 0;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    rateCalls.add(rate);
    return null;
  }

  @override
  Future<dynamic> stop() async {
    stopCalls++;
    return null;
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    speakCalls.add(text);
    if (speakShouldThrow) {
      throw Exception('system tts failed');
    }
    return 1;
  }

  @override
  Future<dynamic> setEngine(String engine) async {
    engineCalls.add(engine);
    return null;
  }

  @override
  Future<dynamic> get getEngines async =>
      const ['com.google.android.tts', 'com.samsung.SMT'];

  @override
  Future<dynamic> isLanguageAvailable(String language) async =>
      language == 'sw' || language.startsWith('sw') ? 1 : 0;

  @override
  Future<dynamic> isLanguageInstalled(String language) async =>
      language == 'sw' || language.startsWith('sw');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLanguageProvider implements LanguageProvider {
  @override
  String get ttsLanguageCode => 'sw';

  @override
  TargetLanguage get selectedLanguage => TargetLanguage.swahili;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAudioPlayer implements AudioPlayer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePiperTts implements PiperSwahiliTts {
  final List<String> calls = [];
  bool shouldThrow = false;

  @override
  bool get isReady => true;

  @override
  bool get initFailed => false;

  @override
  PiperTtsStatus get status => PiperTtsStatus.ready;

  @override
  Future<void> speak(String text, {double speed = 1.0}) async {
    calls.add(text);
    if (shouldThrow) throw Exception('piper failed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AudioController _buildController({
  required SettingsProvider settings,
  required _FakeFlutterTts tts,
  _FakePiperTts? piper,
  TtsAvailabilityChecker? checker,
}) {
  return AudioController(
    tts,
    _FakeLanguageProvider(),
    settings,
    _PassthroughVocabResolver(),
    audioPlayer: _FakeAudioPlayer(),
    speechPlayer: _FakeAudioPlayer(),
    piperTts: piper,
    ttsChecker: checker ?? TtsAvailabilityChecker(tts),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences sp;
  late AppPrefs prefs;
  late SettingsProvider settings;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    getIt.registerLazySingleton<AppPrefs>(() => prefs);
    settings = SettingsProvider(prefs);
    getIt.registerLazySingleton<SettingsProvider>(() => settings);
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('AudioController.mapUiSpeedToFlutterTtsRate', () {
    test('1.0x UI maps to flutter_tts normal 0.5', () {
      expect(AudioController.mapUiSpeedToFlutterTtsRate(1.0), 0.5);
    });

    test('0.8x and 1.2x scale around normal', () {
      expect(AudioController.mapUiSpeedToFlutterTtsRate(0.8), closeTo(0.4, 1e-9));
      expect(AudioController.mapUiSpeedToFlutterTtsRate(1.2), closeTo(0.6, 1e-9));
    });
  });

  group('AudioController TTS engine routing', () {
    test('system mode uses device TTS and does not call Piper', () async {
      final tts = _FakeFlutterTts();
      final piper = _FakePiperTts();
      final controller =
          _buildController(settings: settings, tts: tts, piper: piper);

      final result = await controller.speakWithResult('Habari');

      expect(result.source, TtsSpeakSource.system);
      expect(result.usedFallback, isFalse);
      expect(tts.languageCalls, isNotEmpty);
      expect(tts.languageCalls.last, anyOf('sw', 'sw-KE', 'sw-TZ', 'sw_KE', 'sw_TZ'));
      expect(tts.rateCalls, [0.5]);
      expect(tts.speakCalls, ['Habari']);
      expect(piper.calls, isEmpty);
    });

    test('system mode falls back to Piper when device TTS fails', () async {
      final tts = _FakeFlutterTts(speakShouldThrow: true);
      final piper = _FakePiperTts();
      final controller =
          _buildController(settings: settings, tts: tts, piper: piper);

      final result = await controller.speakWithResult('Habari');

      expect(result.source, TtsSpeakSource.piper);
      expect(result.usedFallback, isTrue);
      expect(tts.speakCalls, ['Habari']);
      expect(piper.calls, ['Habari']);
      // System stop before piper.
      expect(tts.stopCalls, greaterThan(0));
    });

    test('system mode falls back to Piper when setLanguage fails', () async {
      final tts = _FakeFlutterTts(setLanguageSucceeds: false);
      final piper = _FakePiperTts();
      final controller =
          _buildController(settings: settings, tts: tts, piper: piper);

      final result = await controller.speakWithResult('Habari');

      expect(result.source, TtsSpeakSource.piper);
      expect(result.usedFallback, isTrue);
      expect(tts.languageCalls, isNotEmpty);
      expect(tts.speakCalls, isEmpty);
      expect(piper.calls, ['Habari']);
    });

    test('offline mode uses Piper first and skips device TTS speak', () async {
      final tts = _FakeFlutterTts();
      final piper = _FakePiperTts();
      await settings.setTtsEngine(TtsEngine.offline);
      final controller =
          _buildController(settings: settings, tts: tts, piper: piper);

      final result = await controller.speakWithResult('Habari');

      expect(result.source, TtsSpeakSource.piper);
      expect(result.usedFallback, isFalse);
      expect(piper.calls, ['Habari']);
      expect(tts.speakCalls, isEmpty);
      // stopSystemTts before piper.
      expect(tts.stopCalls, greaterThan(0));
    });

    test(
      'offline mode falls back to device TTS and marks usedFallback',
      () async {
        final tts = _FakeFlutterTts();
        final piper = _FakePiperTts()..shouldThrow = true;
        await settings.setTtsEngine(TtsEngine.offline);
        final controller =
            _buildController(settings: settings, tts: tts, piper: piper);

        final result = await controller.speakWithResult('Habari');

        expect(result.source, TtsSpeakSource.system);
        expect(result.usedFallback, isTrue);
        expect(result.error, isNotNull);
        expect(piper.calls, ['Habari']);
        expect(tts.speakCalls, ['Habari']);
      },
    );

    test('both engines fail → TtsSpeakSource.failed', () async {
      final tts = _FakeFlutterTts(speakShouldThrow: true);
      final piper = _FakePiperTts()..shouldThrow = true;
      await settings.setTtsEngine(TtsEngine.offline);
      final controller =
          _buildController(settings: settings, tts: tts, piper: piper);

      final result = await controller.speakWithResult('Habari');

      expect(result.source, TtsSpeakSource.failed);
      expect(result.error, isNotNull);
    });

    test('rebindSystemTts forces engine reconfigure and clears language cache',
        () async {
      final tts = _FakeFlutterTts();
      final controller = _buildController(settings: settings, tts: tts);

      await controller.speak('Habari');
      final languagesAfterFirst = List<String>.from(tts.languageCalls);

      await controller.rebindSystemTts();
      await controller.speak('Jambo');

      expect(tts.languageCalls.length, greaterThan(languagesAfterFirst.length));
      expect(tts.speakCalls, ['Habari', 'Jambo']);
    });
  });
}
