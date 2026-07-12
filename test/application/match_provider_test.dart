// Unit tests for [MatchProvider] after DI injection + field encapsulation.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/application/match_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/domain/audio/vocab_audio_resolver.dart';
import 'package:varnamala/service/locator.dart';

class _FakeFlutterTts implements FlutterTts {
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

class _PassthroughVocabResolver implements VocabAudioResolver {
  @override
  ResolvedVocabAudio resolve(String wordId) =>
      ResolvedVocabAudio(speakText: wordId);
}

class _SilentAudioController extends AudioController {
  _SilentAudioController(SettingsProvider settings)
      : super(
          _FakeFlutterTts(),
          _FakeLanguageProvider(),
          settings,
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
  late AppPrefs prefs;
  late MatchProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    final settings = SettingsProvider(prefs);
    provider = MatchProvider(_SilentAudioController(settings), prefs);
  });

  tearDown(() {
    provider.pauseTimer();
  });

  test('initializeGame populates word lists and resets score', () {
    provider.initializeGame();

    expect(provider.englishWords, hasLength(8));
    expect(provider.targetWords, hasLength(8));
    expect(provider.wordPairs, isNotNull);
    expect(provider.wordPairs!.length, 8);
    expect(provider.sessionScore, 0);
    expect(provider.roundsCompleted, 0);
    expect(provider.isGameOver, isFalse);
    expect(provider.selectedEnglishWord, isNull);
    expect(provider.selectedTargetWord, isNull);
    expect(provider.countdownNotifier.value, 90);
  });

  test('correct match increments score and clears selection', () async {
    provider.initializeGame();
    provider.pauseTimer(); // avoid wall-clock noise

    final english = provider.englishWords.first;
    final target = provider.wordPairs![english]!;

    provider.selectEnglishWord(english);
    expect(provider.selectedEnglishWord, english);

    provider.selectTargetWord(target);
    // checkMatch is async; wait for sound + 500ms animation delay.
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(provider.sessionScore, 2);
    expect(provider.currentRoundMatches, 1);
    expect(provider.selectedEnglishWord, isNull);
    expect(provider.selectedTargetWord, isNull);
    // Matched pair is replaced: lists still size 8.
    expect(provider.englishWords, hasLength(8));
    expect(provider.targetWords, hasLength(8));
  });

  test('incorrect match clears selection without scoring', () async {
    provider.initializeGame();
    provider.pauseTimer();

    final english = provider.englishWords.first;
    final correct = provider.wordPairs![english]!;
    final wrong = provider.targetWords.firstWhere((w) => w != correct);

    provider.selectEnglishWord(english);
    provider.selectTargetWord(wrong);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(provider.sessionScore, 0);
    expect(provider.currentRoundMatches, 0);
    expect(provider.selectedEnglishWord, isNull);
    expect(provider.selectedTargetWord, isNull);
  });

  test('pauseTimer stops countdown', () async {
    provider.initializeGame();
    final before = provider.countdownNotifier.value;
    provider.pauseTimer();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(provider.countdownNotifier.value, before);
    expect(provider.isGameOver, isFalse);
  });
}
