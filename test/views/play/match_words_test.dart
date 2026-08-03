import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/match_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/audio/vocab_audio_resolver.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/play/match_words.dart';

class _FakeFlutterTts implements FlutterTts {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeLanguageProvider implements LanguageProvider {
  @override
  String get ttsLanguageCode => 'tr';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeAudioPlayer implements AudioPlayer {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _PassthroughVocabResolver implements VocabAudioResolver {
  @override
  ResolvedVocabAudio resolve(String wordId) =>
      ResolvedVocabAudio(speakText: wordId);
}

class _SilentAudio extends AudioController {
  _SilentAudio(SettingsProvider settings, AccessibilityProvider acc)
      : super(
          _FakeFlutterTts(),
          _FakeLanguageProvider(),
          settings,
          acc,
          _PassthroughVocabResolver(),
          audioPlayer: _FakeAudioPlayer(),
          speechPlayer: _FakeAudioPlayer(),
        );
  @override
  Future<void> playRandomErrorSound() async {}
  @override
  Future<void> playRandomLevelUpSound() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await getIt.reset();
    getIt.registerLazySingleton<AppPrefs>(() => prefs);
    getIt.registerLazySingleton<SettingsProvider>(
      () => SettingsProvider(prefs),
    );
    getIt.registerLazySingleton<AccessibilityProvider>(
      () => AccessibilityProvider(prefs),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('MatchWordsPage shows title after init', (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // App bar title + timer can overflow on tight widths in tests.
    final old = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('A RenderFlex overflowed')) return;
      old?.call(details);
    };
    addTearDown(() => FlutterError.onError = old);

    final settings = getIt<SettingsProvider>();
    final acc = getIt<AccessibilityProvider>();
    final match = MatchProvider(_SilentAudio(settings, acc), prefs);
    final game = GameProvider.forTesting(prefs);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MatchProvider>.value(value: match),
          ChangeNotifierProvider<GameProvider>.value(value: game),
        ],
        child: const MaterialApp(home: MatchWordsPage()),
      ),
    );
    // Post-frame initializeGame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('匹配狂热'), findsOneWidget);
    match.pauseTimer();
  });
}
