// End-to-end lesson path (host): load synthetic lesson → answer → complete →
// progress recorded. Runs under `flutter test` (no device).

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/achievements_provider.dart';
import 'package:varnamala/application/accessibility_provider.dart';
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/language_provider.dart';
import '../helpers/in_memory_course_db.dart';
import 'package:varnamala/application/lesson_completion_coordinator.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/application/lesson_viewmodel.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/progress_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
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
  final Lesson lesson;
  _FakeCourseProvider(this.lesson);
  @override
  Lesson? findLessonById(String id) => id == lesson.id ? lesson : null;
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

Lesson _mcqLesson() => const Lesson(
      id: 'lesson-e2e',
      name: 'E2E Lesson',
      template: LessonTemplate.legacy,
      content: LessonContent(
        stages: [
          Stage(
            id: 's1',
            name: 'Stage',
            items: [
              Interaction.multipleChoice(
                id: 'q1',
                prompt: 'Hello?',
                options: ['Habari', 'Asante'],
                correctIndex: 0,
              ),
              Interaction.multipleChoice(
                id: 'q2',
                prompt: 'Thanks?',
                options: ['Asante', 'Habari'],
                correctIndex: 0,
              ),
            ],
          ),
        ],
      ),
    );

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

  test('lesson flow: answer all → complete → progress recorded', () async {
    final lesson = _mcqLesson();
    final game = GameProvider.forTesting(prefs);
    final link = LessonLinkStore(prefs);
    final srsDao = emptySrsStateDao();
    final srs = SrsProvider(prefs, link, srsDao);
    final mistakes = MistakeProvider(prefs);
    final grammar = GrammarReviewProvider(prefs, link, srsDao);
    final study = _FakeStudyStats(prefs);
    final coordinator = LessonCompletionCoordinator(
      game,
      GemsProvider(prefs),
      AchievementsProvider(prefs),
      study,
    );
    final vm = LessonViewModel(
      _FakeCourseProvider(lesson),
      _FakeAudioController(),
      srs,
      mistakes,
      grammar,
      coordinator,
    );
    final progress = ProgressProvider(game);

    vm.loadLessonInstance(lesson);
    expect(vm.totalInteractionCount, 2);

    vm.submitInteraction(true, userAnswerText: 'Habari');
    vm.advance();
    vm.submitInteraction(true, userAnswerText: 'Asante');
    vm.advance();

    expect(vm.isComplete, isTrue);

    await game.recordLessonCompletion(
      lessonId: lesson.id,
      wasPerfect: true,
    );

    expect(progress.isLessonCompleted(lesson.id), isTrue);
    expect(progress.isLessonPerfect(lesson.id), isTrue);
    expect(game.isLessonCompleted(lesson.id), isTrue);
  });
}
