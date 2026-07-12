// Regression: the mastery-retry dialog used to display the placeholder
// `accuracy = total` so users saw no feedback. After the fix, the dialog
// uses `correctAnswers` / `totalInteractionCount` from LessonViewModel.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/achievements_provider.dart';
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/application/lesson_completion_coordinator.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/application/lesson_viewmodel.dart';
import 'package:varnamala/application/mistake_provider.dart'; // MistakeProvider for StudyStatsProvider
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/application/study_stats_provider.dart';
import 'package:varnamala/data/study_log_repository.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/audio/vocab_audio_resolver.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/lesson_content.dart';
import 'package:varnamala/domain/course/stage.dart';
import 'package:varnamala/domain/study/study_log.dart';
import 'package:varnamala/service/locator.dart';

class _PassthroughVocabResolver implements VocabAudioResolver {
  @override
  ResolvedVocabAudio resolve(String wordId) =>
      ResolvedVocabAudio(speakText: wordId);
}

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

class _FakeAudioController extends AudioController {
  _FakeAudioController()
      : super(
          _FakeFlutterTts(),
          _FakeLanguageProvider(),
          getIt<SettingsProvider>(),
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
  final Lesson? lesson;
  _FakeCourseProvider(this.lesson);
  @override
  Lesson? findLessonById(String id) => lesson;
}

class _FakeAchievementsProvider extends AchievementsProvider {
  _FakeAchievementsProvider() : super(_FakeAppPrefs());
  @override
  Future<void> checkLessonMilestones({
    required int lessonsCompleted,
    required int perfectLessons,
  }) async {}
}

class _FakeStudyStatsProvider extends StudyStatsProvider {
  _FakeStudyStatsProvider(AppPrefs appPrefs)
      : super(StudyLogRepository(appPrefs), MistakeProvider(appPrefs));
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

class _FakeAppPrefs implements AppPrefs {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Lesson _masteryLesson() {
  final items = <Interaction>[];
  for (var i = 0; i < 6; i++) {
    items.add(
      Interaction.multipleChoice(
        id: 'mcq-$i',
        prompt: 'Q$i',
        options: const ['Correct', 'Wrong'],
        correctIndex: 0,
      ),
    );
  }
  return Lesson(
    id: 'l-mastery-stats',
    name: 'Mastery',
    template: LessonTemplate.mastery,
    content: LessonContent(
      stages: [
        Stage(id: 's1', name: 'Stage', items: items),
      ],
    ),
  );
}

LessonViewModel _harness(AppPrefs prefs, Lesson lesson) {
  final linkStore = LessonLinkStore(prefs);
  final gameProvider = GameProvider.forTesting(prefs);
  final gemsProvider = GemsProvider(prefs);
  final achievementsProvider = _FakeAchievementsProvider();
  final studyStatsProvider = _FakeStudyStatsProvider(prefs);
  return LessonViewModel(
    _FakeCourseProvider(lesson),
    _FakeAudioController(),
    SrsProvider(prefs, linkStore),
    MistakeProvider(prefs),
    GrammarReviewProvider(prefs, linkStore),
    LessonCompletionCoordinator(
      gameProvider,
      gemsProvider,
      achievementsProvider,
      studyStatsProvider,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences sp;
  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    // _FakeAudioController extends AudioController, whose constructor reads
    // ttsSpeed from SettingsProvider via getIt. Register both before building
    // the harness (which constructs the audio controller).
    await getIt.reset();
    getIt.registerLazySingleton<AppPrefs>(() => prefs);
    getIt.registerLazySingleton<SettingsProvider>(() => SettingsProvider(prefs));
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('mastery 4/6 surfaces real stats, not placeholder', () async {
    final lesson = _masteryLesson();
    final vm = _harness(prefs, lesson);

    await vm.loadLesson(lesson.id);
    for (var i = 0; i < 6; i++) {
      final correct = i < 4;
      vm.submitInteraction(correct, userAnswerText: correct ? 'Correct' : 'Wrong');
      vm.advance();
    }
    await pumpEventQueue();

    expect(vm.isMastery, isTrue);
    expect(vm.masteryPassed, isFalse);
    // The dialog now consumes these:
    expect(vm.correctAnswers, 4);
    expect(vm.totalInteractionCount, 6);
    // 4/6 = 67% rounded.
    final expectedPct = ((4 / 6) * 100).round();
    expect(expectedPct, 67);
  });

  test('mastery 5/6: correctAnswers reflects the actual wins', () async {
    final lesson = _masteryLesson();
    final vm = _harness(prefs, lesson);

    await vm.loadLesson(lesson.id);
    for (var i = 0; i < 6; i++) {
      final correct = i < 5;
      vm.submitInteraction(correct, userAnswerText: correct ? 'Correct' : 'Wrong');
      vm.advance();
    }
    await pumpEventQueue();

    expect(vm.isMastery, isTrue);
    expect(vm.masteryPassed, isTrue);
    expect(vm.correctAnswers, 5);
    expect(vm.totalInteractionCount, 6);
  });

  test('lesson completion exposes incorrectAnswers, duration and per-question results', () async {
    final lesson = _masteryLesson();
    final vm = _harness(prefs, lesson);

    await vm.loadLesson(lesson.id);
    for (var i = 0; i < 6; i++) {
      final correct = i < 4;
      vm.submitInteraction(correct, userAnswerText: correct ? 'Correct' : 'Wrong');
      vm.advance();
    }
    await pumpEventQueue();

    expect(vm.incorrectAnswers, 2);
    expect(vm.durationSeconds, greaterThanOrEqualTo(0));

    final results = vm.questionResults;
    expect(results.length, 6);
    expect(results.where((r) => r.correct).length, 4);
    expect(results.where((r) => !r.correct).length, 2);
    expect(results.first.prompt, 'Q0');
  });
}
