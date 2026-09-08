import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/audio/vocab_audio_resolver.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/tts_availability_checker.dart';

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
      language == 'tr' || language.startsWith('tr') ? 1 : 0;

  @override
  Future<dynamic> isLanguageInstalled(String language) async =>
      language == 'tr' || language.startsWith('tr');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLanguageProvider implements LanguageProvider {
  @override
  String get ttsLanguageCode => 'tr';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAudioPlayer implements AudioPlayer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AudioController _buildController({
  required SettingsProvider settings,
  required _FakeFlutterTts tts,
  TtsAvailabilityChecker? checker,
}) {
  return AudioController(
    tts,
    _FakeLanguageProvider(),
    settings,
    getIt<AccessibilityProvider>(),
    _PassthroughVocabResolver(),
    audioPlayer: _FakeAudioPlayer(),
    speechPlayer: _FakeAudioPlayer(),
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
    getIt.registerLazySingleton<AccessibilityProvider>(
      () => AccessibilityProvider(prefs),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('AudioController.mapUiSpeedToFlutterTtsRate', () {
    test('1.0x UI maps to flutter_tts normal 0.5', () {
      expect(AudioController.mapUiSpeedToFlutterTtsRate(1.0), 0.5);
    });

    test('0.8x and 1.2x scale around normal', () {
      expect(
          AudioController.mapUiSpeedToFlutterTtsRate(0.8), closeTo(0.4, 1e-9));
      expect(
          AudioController.mapUiSpeedToFlutterTtsRate(1.2), closeTo(0.6, 1e-9));
    });
  });

  group('AudioController TTS routing', () {
    test('system mode uses device TTS', () async {
      final tts = _FakeFlutterTts();
      final controller = _buildController(settings: settings, tts: tts);

      final result = await controller.speakWithResult('Merhaba');

      expect(result.source, TtsSpeakSource.system);
      expect(result.usedFallback, isFalse);
      expect(tts.languageCalls, isNotEmpty);
      expect(tts.languageCalls.last, anyOf('tr', 'tr-TR', 'tr_TR'));
      expect(tts.rateCalls, [0.5]);
      expect(tts.speakCalls, ['Merhaba']);
    });

    test('device TTS failure → TtsSpeakSource.failed', () async {
      final tts = _FakeFlutterTts(speakShouldThrow: true);
      final controller = _buildController(settings: settings, tts: tts);

      final result = await controller.speakWithResult('Merhaba');

      expect(result.source, TtsSpeakSource.failed);
      expect(result.error, isNotNull);
      expect(tts.speakCalls, ['Merhaba']);
    });

    test('setLanguage failure → TtsSpeakSource.failed', () async {
      final tts = _FakeFlutterTts(setLanguageSucceeds: false);
      final controller = _buildController(settings: settings, tts: tts);

      final result = await controller.speakWithResult('Merhaba');

      expect(result.source, TtsSpeakSource.failed);
      expect(tts.languageCalls, isNotEmpty);
      expect(tts.speakCalls, isEmpty);
    });

    test('rebindSystemTts forces engine reconfigure and clears language cache',
        () async {
      final tts = _FakeFlutterTts();
      final controller = _buildController(settings: settings, tts: tts);

      await controller.speak('Merhaba');
      final languagesAfterFirst = List<String>.from(tts.languageCalls);

      await controller.rebindSystemTts();
      await controller.speak('Selam');

      expect(tts.languageCalls.length, greaterThan(languagesAfterFirst.length));
      expect(tts.speakCalls, ['Merhaba', 'Selam']);
    });
  });
}
