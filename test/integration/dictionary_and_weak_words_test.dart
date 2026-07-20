// Dictionary search + weak-word quiz assembly + load into LessonViewModel.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/achievements_provider.dart';
import 'package:varnamala/application/accessibility_provider.dart';
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/dictionary_search.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/application/lesson_completion_coordinator.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/application/lesson_viewmodel.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/application/study_stats_provider.dart';
import 'package:varnamala/application/weak_word_quiz_assembler.dart';
import 'package:varnamala/courses/languages/vocab.dart';
import 'package:varnamala/data/study_log_repository.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/audio/vocab_audio_resolver.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/mistake_entry.dart';
import 'package:varnamala/domain/course/word_entry.dart';
import 'package:varnamala/domain/study/study_log.dart';
import 'package:varnamala/service/locator.dart';

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

class _FakeAudioController extends AudioController {
  _FakeAudioController()
      : super(
          _FakeFlutterTts(),
          _FakeLanguageProvider(),
          getIt<SettingsProvider>(),
          getIt<AccessibilityProvider>(),
          _PassthroughVocabResolver(),
          audioPlayer: _FakeAudioPlayer(),
          speechPlayer: _FakeAudioPlayer(),
        );
  @override
  Future<void> speak(String text, {double? speed}) async {}
  @override
  Future<void> speakFromAsset(String assetPath) async {}
  @override
  Future<void> playRandomErrorSound() async {}
  @override
  Future<void> playRandomLevelUpSound() async {}
}

class _FakeCourseProvider extends CourseProvider {
  @override
  Lesson? findLessonById(String id) => null;
}

class _FakeStudyStats extends StudyStatsProvider {
  _FakeStudyStats(AppPrefs p)
      : super(StudyLogRepository(p), MistakeProvider(p));
  @override
  Future<void> recordActivity({
    required StudyActivityType type,
    String? lessonId,
    int xpEarned = 0,
    int durationSeconds = 0,
    int correctCount = 0,
    int incorrectCount = 0,
    List<String> wordIds = const [],
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  final now = DateTime(2026, 7, 11, 12);

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

    vocabById
      ..clear()
      ..addAll({
        'w-habari': const WordEntry(
          id: 'w-habari',
          term: 'Habari',
          translation: 'Hello',
          tags: ['greeting'],
        ),
        'w-asante': const WordEntry(
          id: 'w-asante',
          term: 'Asante',
          translation: 'Thanks',
        ),
        'w-sawa': const WordEntry(
          id: 'w-sawa',
          term: 'Sawa',
          translation: 'OK',
        ),
        'w-ndio': const WordEntry(
          id: 'w-ndio',
          term: 'Ndio',
          translation: 'Yes',
        ),
      });
  });

  tearDown(() async {
    vocabById.clear();
    await getIt.reset();
  });

  test('dictionary hit + weak quiz load and answer one item', () async {
    expect(searchDictionary('habari'), isNotEmpty);
    expect(searchDictionary('habari').single.kind, DictionaryHitKind.vocab);

    final entries = [
      for (var i = 0; i < 2; i++)
        MistakeEntry(
          id: 'm$i',
          lessonId: 'l1',
          stageId: 's1',
          interactionId: 'i1',
          wordId: 'w-habari',
          userAnswer: 'x',
          correctAnswer: 'Hello',
          timestamp: now.subtract(Duration(days: i)),
        ),
    ];
    final weak = WeakWordQuizAssembler.aggregateWeakWords(entries, now: now);
    expect(weak, isNotEmpty);

    final lesson = WeakWordQuizAssembler.assembleFromWeakWords(weak);
    expect(lesson.flattenedStages.first.items, isNotEmpty);

    final game = GameProvider.forTesting(prefs);
    final link = LessonLinkStore(prefs);
    final vm = LessonViewModel(
      _FakeCourseProvider(),
      _FakeAudioController(),
      SrsProvider(prefs, link),
      MistakeProvider(prefs),
      GrammarReviewProvider(prefs, link),
      LessonCompletionCoordinator(
        game,
        GemsProvider(prefs),
        AchievementsProvider(prefs),
        _FakeStudyStats(prefs),
      ),
    );

    vm.loadLessonInstance(lesson);
    expect(vm.currentInteraction, isNotNull);

    final item = vm.currentInteraction!;
    if (item is MultipleChoice) {
      vm.submitInteraction(
        true,
        userAnswerText: item.options[item.correctIndex],
      );
    } else {
      vm.submitInteraction(true, userAnswerText: 'ok');
    }
    expect(vm.hasSubmitted, isTrue);
  });
}
