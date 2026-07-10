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
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/service/piper_swahili_tts.dart';
import 'package:varnamala/service/tts_availability_checker.dart';

class _FakeFlutterTts implements FlutterTts {
  _FakeFlutterTts({this.speakShouldThrow = false});

  final bool speakShouldThrow;

  final List<String> speakCalls = [];
  final List<String> languageCalls = [];
  final List<double> rateCalls = [];
  final List<String> engineCalls = [];
  int stopCalls = 0;

  @override
  Future<dynamic> setLanguage(String language) async {
    languageCalls.add(language);
    return null;
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
    return null;
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

  group('AudioController TTS engine routing', () {
    test('system mode uses device TTS and does not call Piper', () async {
      final tts = _FakeFlutterTts();
      final piper = _FakePiperTts();
      final controller =
          _buildController(settings: settings, tts: tts, piper: piper);

      await controller.speak('Habari');

      expect(tts.languageCalls, isNotEmpty);
      expect(tts.languageCalls.last, anyOf('sw', 'sw-KE', 'sw-TZ', 'sw_KE', 'sw_TZ'));
      expect(tts.rateCalls, [1.0]);
      expect(tts.stopCalls, 1);
      expect(tts.speakCalls, ['Habari']);
      expect(piper.calls, isEmpty);
    });

    test('system mode falls back to Piper when device TTS fails', () async {
      final tts = _FakeFlutterTts(speakShouldThrow: true);
      final piper = _FakePiperTts();
      final controller =
          _buildController(settings: settings, tts: tts, piper: piper);

      await controller.speak('Habari');

      expect(tts.speakCalls, ['Habari']);
      expect(piper.calls, ['Habari']);
    });

    test('offline mode uses Piper first and skips device TTS', () async {
      final tts = _FakeFlutterTts();
      final piper = _FakePiperTts();
      await settings.setTtsEngine(TtsEngine.offline);
      final controller =
          _buildController(settings: settings, tts: tts, piper: piper);

      await controller.speak('Habari');

      expect(piper.calls, ['Habari']);
      expect(tts.speakCalls, isEmpty);
    });

    test('offline mode falls back to device TTS when Piper fails', () async {
      final tts = _FakeFlutterTts();
      final piper = _FakePiperTts()..shouldThrow = true;
      await settings.setTtsEngine(TtsEngine.offline);
      final controller =
          _buildController(settings: settings, tts: tts, piper: piper);

      await controller.speak('Habari');

      expect(piper.calls, ['Habari']);
      expect(tts.languageCalls, isNotEmpty);
      expect(tts.rateCalls, [1.0]);
      expect(tts.stopCalls, 1);
      expect(tts.speakCalls, ['Habari']);
    });

    test('rebindSystemTts forces engine reconfigure and clears language cache',
        () async {
      final tts = _FakeFlutterTts();
      final controller = _buildController(settings: settings, tts: tts);

      await controller.speak('Habari');
      final languagesAfterFirst = List<String>.from(tts.languageCalls);

      await controller.rebindSystemTts();
      await controller.speak('Jambo');

      // Language must be re-applied after rebind even if code is unchanged.
      expect(tts.languageCalls.length, greaterThan(languagesAfterFirst.length));
      expect(tts.speakCalls, ['Habari', 'Jambo']);
    });
  });
}
