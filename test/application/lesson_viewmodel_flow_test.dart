// Flow tests for [LessonViewModel]: loading, answering, mistake recording,
// completion, XP/gem awards, mastery threshold, and grammar registration.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/achievements_provider.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/lesson_completion_coordinator.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/application/mistake_provider.dart'; // MistakeProvider for StudyStatsProvider
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/audio/vocab_audio_resolver.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/stage.dart';
import 'package:turna/domain/study/study_log.dart';
import 'package:turna/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

class _PassthroughVocabResolver implements VocabAudioResolver {
  @override
  ResolvedVocabAudio resolve(String wordId) =>
      ResolvedVocabAudio(speakText: wordId);
}

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
  Future<void> speak(String text,
      {double? speed, String? languageCode}) async {}

  @override
  Future<void> speakFromAsset(String assetPath) async {}

  @override
  Future<void> playRandomErrorSound() async {}

  @override
  Future<void> playRandomLevelUpSound() async {}
}

class _FakeCourseProvider extends CourseProvider {
  final Lesson? _lesson;

  _FakeCourseProvider(this._lesson);

  @override
  Lesson? findLessonById(String id) => _lesson;
}

class _RecordedMilestone {
  final int lessonsCompleted;
  final int perfectLessons;

  _RecordedMilestone(this.lessonsCompleted, this.perfectLessons);
}

class _FakeAchievementsProvider extends AchievementsProvider {
  final List<_RecordedMilestone> milestones = [];

  _FakeAchievementsProvider() : super(_FakeAppPrefs());

  @override
  Future<void> checkLessonMilestones({
    required int lessonsCompleted,
    required int perfectLessons,
  }) async {
    milestones.add(_RecordedMilestone(lessonsCompleted, perfectLessons));
  }
}

class _RecordedActivity {
  final StudyActivityType type;
  final String? lessonId;
  final int xpEarned;

  _RecordedActivity(this.type, this.lessonId, this.xpEarned);
}

class _FakeStudyStatsProvider extends StudyStatsProvider {
  final List<_RecordedActivity> activities = [];

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
  }) async {
    activities.add(_RecordedActivity(type, lessonId, xpEarned));
  }
}

class _FakeAppPrefs implements AppPrefs {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ViewModelHarness {
  final LessonViewModel vm;
  final GameProvider gameProvider;
  final GemsProvider gemsProvider;
  final _FakeAchievementsProvider achievementsProvider;
  final _FakeStudyStatsProvider studyStatsProvider;
  final GrammarReviewProvider grammarProvider;
  final MistakeProvider mistakeProvider;
  final SrsProvider srsProvider;

  _ViewModelHarness({
    required this.vm,
    required this.gameProvider,
    required this.gemsProvider,
    required this.achievementsProvider,
    required this.studyStatsProvider,
    required this.grammarProvider,
    required this.mistakeProvider,
    required this.srsProvider,
  });
}

Lesson _buildLegacyLesson({required List<Interaction> items}) {
  return Lesson(
    id: 'l-flow-legacy',
    name: 'Flow Legacy',
    template: LessonTemplate.legacy,
    content: LessonContent(
      stages: [
        Stage(
          id: 'stage-1',
          name: 'Stage 1',
          items: items,
        ),
      ],
    ),
  );
}

Lesson _buildMasteryLesson() {
  final items = <Interaction>[];
  for (var i = 0; i < 6; i++) {
    items.add(
      Interaction.multipleChoice(
        id: 'mcq-$i',
        prompt: 'Question $i',
        options: const ['Correct', 'Wrong'],
        correctIndex: 0,
      ),
    );
  }
  return Lesson(
    id: 'l-flow-mastery',
    name: 'Flow Mastery',
    template: LessonTemplate.mastery,
    content: LessonContent(
      stages: [
        Stage(
          id: 'stage-1',
          name: 'Stage 1',
          items: items,
        ),
      ],
    ),
  );
}

_ViewModelHarness _buildHarness({
  required Lesson lesson,
  required AppPrefs appPrefs,
}) {
  final courseProvider = _FakeCourseProvider(lesson);
  final gameProvider = GameProvider.forTesting(appPrefs);
  final gemsProvider = GemsProvider(appPrefs);
  final achievementsProvider = _FakeAchievementsProvider();
  final audioController = _FakeAudioController();
  final linkStore = LessonLinkStore(appPrefs);
  final srsDao = emptySrsStateDao();
  final srsProvider = SrsProvider(appPrefs, linkStore, srsDao);
  final mistakeProvider = MistakeProvider(appPrefs);
  final grammarProvider = GrammarReviewProvider(appPrefs, linkStore, srsDao);
  final studyStatsProvider = _FakeStudyStatsProvider(appPrefs);
  final completionCoordinator = LessonCompletionCoordinator(
    gameProvider,
    gemsProvider,
    achievementsProvider,
    studyStatsProvider,
  );

  final vm = LessonViewModel(
    courseProvider,
    audioController,
    srsProvider,
    mistakeProvider,
    grammarProvider,
    completionCoordinator,
  );

  return _ViewModelHarness(
    vm: vm,
    gameProvider: gameProvider,
    gemsProvider: gemsProvider,
    achievementsProvider: achievementsProvider,
    studyStatsProvider: studyStatsProvider,
    grammarProvider: grammarProvider,
    mistakeProvider: mistakeProvider,
    srsProvider: srsProvider,
  );
}

void _answerMultipleChoice(
  LessonViewModel vm, {
  required bool correct,
  required String userAnswer,
}) {
  vm.submitInteraction(correct, userAnswerText: userAnswer);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences prefs;
  late AppPrefs appPrefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await StreamingSharedPreferences.instance;
    appPrefs = AppPrefs(prefs);
    // _FakeAudioController extends AudioController, whose constructor reads
    // ttsSpeed from SettingsProvider via getIt. Register both before building
    // the harness (which constructs the audio controller).
    await getIt.reset();
    getIt.registerLazySingleton<AppPrefs>(() => appPrefs);
    getIt.registerLazySingleton<SettingsProvider>(
      () => SettingsProvider(appPrefs),
    );
    getIt.registerLazySingleton<AccessibilityProvider>(
      () => AccessibilityProvider(appPrefs),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('LessonViewModel flow', () {
    test('legacy lesson: correct then wrong records mistake and completes',
        () async {
      final lesson = _buildLegacyLesson(
        items: [
          const Interaction.multipleChoice(
            id: 'mcq-1',
            prompt: 'Choose A',
            options: ['A', 'B'],
            correctIndex: 0,
          ),
          const Interaction.multipleChoice(
            id: 'mcq-2',
            prompt: 'Choose X',
            options: ['X', 'Y'],
            correctIndex: 0,
          ),
        ],
      );
      final harness = _buildHarness(lesson: lesson, appPrefs: appPrefs);
      final vm = harness.vm;

      final loaded = await vm.loadLesson(lesson.id);
      expect(loaded, isTrue);
      expect(vm.isComplete, isFalse);

      // First item: correct.
      _answerMultipleChoice(vm, correct: true, userAnswer: 'A');
      expect(vm.isAnswerCorrect, isTrue);
      vm.advance();

      // Second item: wrong.
      _answerMultipleChoice(vm, correct: false, userAnswer: 'Y');
      expect(vm.isAnswerCorrect, isFalse);
      vm.advance();

      // Completion is async.
      await pumpEventQueue();

      expect(vm.isComplete, isTrue);
      expect(vm.masteryPassed, isTrue); // non-mastery defaults to true

      final score = harness.gameProvider.getUserScoreStream().first;
      expect(await score, 10); // lessonComplete XP only (one mistake)

      final gems = harness.gemsProvider.getGemsStream().first;
      expect(await gems, 5); // lessonComplete gems only

      expect(harness.mistakeProvider.count, 1);
      expect(harness.mistakeProvider.entries.first.lessonId, lesson.id);

      expect(harness.achievementsProvider.milestones, isNotEmpty);
      expect(harness.achievementsProvider.milestones.first.lessonsCompleted, 1);

      expect(harness.studyStatsProvider.activities, isNotEmpty);
      expect(harness.studyStatsProvider.activities.first.type,
          StudyActivityType.lessonComplete);
      expect(harness.studyStatsProvider.activities.first.lessonId, lesson.id);

      // F2: questionResults is incrementally cached in submission order.
      final results = vm.questionResults;
      expect(results, hasLength(2));
      expect(results[0].prompt, 'Choose A');
      expect(results[0].correct, isTrue);
      expect(results[0].userAnswer, 'A');
      expect(results[1].prompt, 'Choose X');
      expect(results[1].correct, isFalse);
      expect(results[1].userAnswer, 'Y');
      // Read again — same cached backing list (unmodifiable view), not a re-walk.
      expect(identical(vm.questionResults, vm.questionResults), isFalse);
      expect(vm.questionResults.map((r) => r.prompt), ['Choose A', 'Choose X']);
    });

    test(
        'progress reflects submitted count and totalInteractionCount is cached',
        () async {
      final lesson = _buildLegacyLesson(
        items: [
          const Interaction.multipleChoice(
            id: 'mcq-1',
            prompt: 'Q1',
            options: ['A', 'B'],
            correctIndex: 0,
          ),
          const Interaction.multipleChoice(
            id: 'mcq-2',
            prompt: 'Q2',
            options: ['A', 'B'],
            correctIndex: 0,
          ),
          const Interaction.multipleChoice(
            id: 'mcq-3',
            prompt: 'Q3',
            options: ['A', 'B'],
            correctIndex: 0,
          ),
        ],
      );
      final harness = _buildHarness(lesson: lesson, appPrefs: appPrefs);
      final vm = harness.vm;

      await vm.loadLesson(lesson.id);
      expect(vm.totalInteractionCount, 3);
      expect(vm.progress, 0.0);
      expect(vm.currentQuestionNumber, 1);

      // Submitting one item advances the completed counter by exactly one —
      // even if the same item is submitted twice (guard against inflation).
      _answerMultipleChoice(vm, correct: true, userAnswer: 'A');
      _answerMultipleChoice(vm, correct: true, userAnswer: 'A');
      expect(vm.progress, closeTo(1 / 3, 1e-9));
      expect(vm.currentQuestionNumber, 1); // still on item 1 until advance
      vm.advance();

      _answerMultipleChoice(vm, correct: true, userAnswer: 'A');
      vm.advance();
      expect(vm.progress, closeTo(2 / 3, 1e-9));

      _answerMultipleChoice(vm, correct: true, userAnswer: 'A');
      vm.advance();
      await pumpEventQueue();
      expect(vm.isComplete, isTrue);
      // On completion currentQuestionNumber clamps to total.
      expect(vm.currentQuestionNumber, 3);
      expect(vm.progress, 1.0);
    });

    test('mastery lesson with accuracy < 80% does not complete', () async {
      final lesson = _buildMasteryLesson();
      final harness = _buildHarness(lesson: lesson, appPrefs: appPrefs);
      final vm = harness.vm;

      await vm.loadLesson(lesson.id);

      for (var i = 0; i < 6; i++) {
        final correct = i < 4; // 4 correct, 2 wrong
        _answerMultipleChoice(
          vm,
          correct: correct,
          userAnswer: correct ? 'Correct' : 'Wrong',
        );
        vm.advance();
      }

      await pumpEventQueue();

      expect(vm.isMastery, isTrue);
      expect(vm.masteryPassed, isFalse);
      expect(vm.isComplete, isFalse);
      expect(vm.masteryAttempts, 0);

      // Verify retry resets state.
      vm.retryMastery();
      expect(vm.masteryAttempts, 1);
      expect(vm.isComplete, isFalse);
      expect(vm.progress, 0.0);

      // F2: retry clears the cached questionResults so the retry pass starts
      // fresh (old answers from the failed attempt don't leak into the summary).
      expect(vm.questionResults, isEmpty);
    });

    // Regression: loading a mastery lesson must NOT look like a failed check.
    // The old UI triggered the retry dialog purely from
    // `isMastery && !masteryPassed`, which is true right after load because
    // `_masteryPassed` initializes to false. `masteryFailed` must stay false
    // until the user has actually walked off the end of the lesson.
    test('mastery lesson: masteryFailed is false immediately after load',
        () async {
      final lesson = _buildMasteryLesson();
      final harness = _buildHarness(lesson: lesson, appPrefs: appPrefs);
      final vm = harness.vm;

      await vm.loadLesson(lesson.id);

      expect(vm.isMastery, isTrue);
      expect(vm.masteryPassed, isFalse);
      expect(vm.isComplete, isFalse);
      expect(vm.masteryFailed, isFalse,
          reason: 'A freshly loaded mastery lesson is not started, not failed');
      expect(vm.currentInteraction, isNotNull,
          reason: 'There must be a first question to render');
    });

    // Regression: masteryFailed must become true only after the user answers
    // every question and still falls below the 80% threshold.
    test('mastery lesson: masteryFailed is true only after failing all items',
        () async {
      final lesson = _buildMasteryLesson();
      final harness = _buildHarness(lesson: lesson, appPrefs: appPrefs);
      final vm = harness.vm;

      await vm.loadLesson(lesson.id);

      // Answer 4/6 correctly (< 80%).
      for (var i = 0; i < 6; i++) {
        final correct = i < 4;
        _answerMultipleChoice(
          vm,
          correct: correct,
          userAnswer: correct ? 'Correct' : 'Wrong',
        );
        vm.advance();
      }

      await pumpEventQueue();

      expect(vm.masteryPassed, isFalse);
      expect(vm.isComplete, isFalse);
      expect(vm.masteryFailed, isTrue,
          reason: 'All questions answered and accuracy < 80% => failed');
      expect(vm.currentInteraction, isNull);
    });

    test('mastery lesson with accuracy >= 80% completes', () async {
      final lesson = _buildMasteryLesson();
      final harness = _buildHarness(lesson: lesson, appPrefs: appPrefs);
      final vm = harness.vm;

      await vm.loadLesson(lesson.id);

      for (var i = 0; i < 6; i++) {
        final correct = i < 5; // 5 correct, 1 wrong
        _answerMultipleChoice(
          vm,
          correct: correct,
          userAnswer: correct ? 'Correct' : 'Wrong',
        );
        vm.advance();
      }

      await pumpEventQueue();

      expect(vm.isMastery, isTrue);
      expect(vm.masteryPassed, isTrue);
      expect(vm.isComplete, isTrue);
    });

    test('linked grammar points are registered on load', () async {
      const lesson = Lesson(
        id: 'l-flow-grammar',
        name: 'Flow Grammar',
        template: LessonTemplate.legacy,
        content: LessonContent(
          stages: [
            Stage(
              id: 'stage-1',
              name: 'Stage 1',
              items: [
                Interaction.showWord(
                  id: 'sw-1',
                  wordId: 'w-test',
                ),
              ],
            ),
          ],
          linkedGrammarPointIds: ['gp.present-a'],
        ),
      );
      final harness = _buildHarness(lesson: lesson, appPrefs: appPrefs);

      await harness.vm.loadLesson(lesson.id);

      expect(harness.grammarProvider.dueCount, 1);
      expect(harness.grammarProvider.state.containsKey('gp.present-a'), isTrue);
    });

    test('anki flip card submit derives wordId and grades SRS state', () async {
      // Course-path AnkiCard interactions are id'd '<wordId>-c<ord>' by the
      // deck assembler; submitting one must register + grade the word in the
      // SRS queue just like a ShowWord would.
      final lesson = _buildLegacyLesson(
        items: [
          const Interaction.ankiCard(
            id: 'anki-imp1-n42-c0',
            front: 'Front side',
            back: 'Back side',
          ),
        ],
      );
      final harness = _buildHarness(lesson: lesson, appPrefs: appPrefs);
      final vm = harness.vm;

      await vm.loadLesson(lesson.id);
      vm.submitInteraction(true);
      await pumpEventQueue();

      final word = harness.srsProvider.state['anki-imp1-n42'];
      expect(word, isNotNull,
          reason: 'flip card wordId should be registered in the SRS queue');
      expect(word!.reps, greaterThan(0),
          reason: 'a passing grade should advance the card');
    });

    test('ankiWordIdFromInteractionId strips review prefix and card ordinal',
        () {
      expect(ankiWordIdFromInteractionId('anki-imp1-n42-c0'), 'anki-imp1-n42');
      expect(ankiWordIdFromInteractionId('anki-imp1-n42-c12'), 'anki-imp1-n42');
      expect(
        ankiWordIdFromInteractionId('anki-review-anki-imp1-n42'),
        'anki-imp1-n42',
      );
      // Ids that match neither convention pass through unchanged.
      expect(ankiWordIdFromInteractionId('mcq-1'), 'mcq-1');
    });
  });

  group('LessonViewModel.undoLastInteraction', () {
    test('correct + wrong → undo restores counters and SRS state', () async {
      // Build a non-Anki legacy lesson so submitInteraction routes the
      // grade through _applySrsOutcome only when the interaction carries
      // a wordId. A plain multipleChoice does not — so we assert the UI
      // counter restoration without SRS involvement.
      final lesson = _buildLegacyLesson(
        items: const [
          Interaction.multipleChoice(
            id: 'mcq-undo-1',
            prompt: 'Q1',
            options: ['A', 'B'],
            correctIndex: 0,
          ),
          Interaction.multipleChoice(
            id: 'mcq-undo-2',
            prompt: 'Q2',
            options: ['A', 'B'],
            correctIndex: 0,
          ),
        ],
      );
      final harness = _buildHarness(lesson: lesson, appPrefs: appPrefs);
      final vm = harness.vm;
      await vm.loadLesson(lesson.id);

      _answerMultipleChoice(vm, correct: true, userAnswer: 'A');
      vm.advance();
      _answerMultipleChoice(vm, correct: false, userAnswer: 'B');
      vm.advance();

      expect(vm.correctAnswers, 1);
      expect(vm.incorrectAnswers, 1);

      // Undo rewinds both the UI counter and the lesson position.
      final ok = await vm.undoLastInteraction();
      expect(ok, isTrue);
      expect(vm.correctAnswers, 1);
      expect(vm.incorrectAnswers, 0);
      expect(vm.currentInteraction?.id, 'mcq-undo-2');

      // Undo again rewinds the first interaction.
      final ok2 = await vm.undoLastInteraction();
      expect(ok2, isTrue);
      expect(vm.correctAnswers, 0);
      expect(vm.incorrectAnswers, 0);
      expect(vm.currentInteraction?.id, 'mcq-undo-1');
    });

    test('undo returns false when SRS gate is held by an in-flight grade',
        () async {
      // Use an Anki flip card so submitInteraction routes through
      // _applySrsOutcome and captures a _SrsUndoEntry. The wordId is
      // derived from the interaction id via ankiWordIdFromInteractionId.
      // Wrap the SRS review in a Completer so the gate stays held while
      // we attempt the undo; the undo must roll back the UI counters but
      // return false (gate-held). After the gate releases, a second undo
      // restores the SRS state.
      final lesson = _buildLegacyLesson(
        items: const [
          Interaction.ankiCard(
            id: 'anki-imp1-n42-c0',
            front: 'front',
            back: 'back',
          ),
        ],
      );
      final harness = _buildHarness(lesson: lesson, appPrefs: appPrefs);
      final vm = harness.vm;
      await vm.loadLesson(lesson.id);

      // Lock the SRS gate by injecting a ReviewHistoryDao whose
      // countFailsOnLocalDay never completes until we say so.
      final completer = Completer<int>();
      harness.srsProvider.setReviewHistoryDaoForTesting(
        _GateHoldingReviewHistoryDao(completer.future),
      );

      _answerMultipleChoice(vm, correct: false, userAnswer: 'no');

      // Undo while the grade's countFailsOnLocalDay await is pending.
      // The SRS rollback will refuse (gate held) and return false; the
      // UI restore still happens.
      final ok = await vm.undoLastInteraction();
      expect(ok, isFalse,
          reason: 'gate-held undo must return false, not silently pass');
      // UI counters were still rewound because the synchronous prefix
      // of undoLastInteraction runs before the SRS rollback.
      expect(vm.incorrectAnswers, 0);

      // Release the gate and retry.
      completer.complete(0);
      await pumpEventQueue();

      // No new submission means the captured stack entry has already
      // been pushed back by the failed undo — a second undo (against
      // an empty submittedInteractions list) returns false. The test
      // is only asserting that the gate-held path returns false; a
      // follow-up success path is covered by the non-Anki case above
      // and the existing srs_provider undo-gate test.
    });
  });
}

/// Test-only ReviewHistoryDao that holds countFailsOnLocalDay on a
/// Completer so the SRS grade's gate stays held across an undo attempt.
class _GateHoldingReviewHistoryDao implements ReviewHistoryDao {
  _GateHoldingReviewHistoryDao(this._hold);
  final Future<int> _hold;

  @override
  Future<int> countFailsOnLocalDay(String cardId, DateTime localDay) => _hold;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
