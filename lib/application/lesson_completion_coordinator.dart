// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/result.dart';
import 'package:turna/domain/study/study_log.dart';

/// Orchestrates side-effects when a lesson finishes (XP, gems, progress,
/// study stats, achievements). Kept separate from [LessonViewModel] so the
/// view-model only owns in-lesson progression state.
///
/// Order matters for the achievement engine (plan §5.2): every authoritative
/// write (XP, lesson ids, study log with wordIds) lands **before** the single
/// achievement evaluation at the end, so the evaluator always sees a
/// consistent metric snapshot.
@lazySingleton
class LessonCompletionCoordinator {
  final GameProvider _gameProvider;
  final GemsProvider _gemsProvider;
  final AchievementService _achievementService;
  final StudyStatsProvider _studyStatsProvider;

  LessonCompletionCoordinator(
    this._gameProvider,
    this._gemsProvider,
    this._achievementService,
    this._studyStatsProvider,
  );

  /// Run completion side-effects. Each step is independent: one failure does
  /// not abort the others.
  Future<void> complete({
    required String lessonId,
    required bool wasPerfect,
    required int correctAnswers,
    required int incorrectAnswers,
    required DateTime? lessonStartTime,
    List<String> wordIds = const [],
  }) async {
    final completedAt = DateTime.now();
    await Future.wait([
      _runSideEffect(
        'award lesson-complete XP',
        () => _gameProvider.awardXP(XPEvent.lessonComplete),
      ),
      _runSideEffect(
        'earn lesson-complete gems',
        () => _gemsProvider.earnGems(
          GemEvent.lessonComplete,
          eventId: GemRewardEventIds.lesson(lessonId, completedAt),
        ),
      ),
    ]);

    if (wasPerfect) {
      await Future.wait([
        _runSideEffect(
          'award perfect-lesson XP',
          () => _gameProvider.awardXP(XPEvent.perfectLesson),
        ),
        _runSideEffect(
          'earn perfect-lesson gems',
          () => _gemsProvider.earnGems(
            GemEvent.perfectLesson,
            eventId: GemRewardEventIds.perfectLesson(lessonId, completedAt),
          ),
        ),
      ]);
    }

    await _runSideEffect(
      'record lesson completion',
      () => _gameProvider.recordLessonCompletion(
        lessonId: lessonId,
        wasPerfect: wasPerfect,
      ),
    );

    await _runSideEffect('record study stats', () async {
      final duration = lessonStartTime != null
          ? DateTime.now().difference(lessonStartTime).inSeconds
          : 0;
      final xpEarned = wasPerfect
          ? XPEvent.lessonComplete.base + XPEvent.perfectLesson.base
          : XPEvent.lessonComplete.base;
      await _studyStatsProvider.recordActivity(
        type: StudyActivityType.lessonComplete,
        lessonId: lessonId,
        xpEarned: xpEarned,
        durationSeconds: duration,
        correctCount: correctAnswers,
        incorrectCount: incorrectAnswers,
        wordIds: wordIds,
      );
    });

    // Single evaluation point after every authoritative write above.
    await _runSideEffect('record studied words', () async {
      await _achievementService.recordStudiedWords(wordIds);
    });
    await _runSideEffect('evaluate achievements', () async {
      await _achievementService.evaluateAndReward();
    });
  }

  Future<void> _runSideEffect(
    String label,
    Future<void> Function() action,
  ) async {
    final result = await Result.guard(action);
    if (result.isFailure) {
      logger.w('Lesson completion: $label failed', error: result.error);
    }
  }
}
