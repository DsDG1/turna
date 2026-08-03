// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/achievements_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/result.dart';
import 'package:turna/domain/study/study_log.dart';

/// Orchestrates side-effects when a lesson finishes (XP, gems, progress,
/// achievements, study stats). Kept separate from [LessonViewModel] so the
/// view-model only owns in-lesson progression state.
@lazySingleton
class LessonCompletionCoordinator {
  final GameProvider _gameProvider;
  final GemsProvider _gemsProvider;
  final AchievementsProvider _achievementsProvider;
  final StudyStatsProvider _studyStatsProvider;

  LessonCompletionCoordinator(
    this._gameProvider,
    this._gemsProvider,
    this._achievementsProvider,
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
  }) async {
    await Future.wait([
      _runSideEffect(
        'award lesson-complete XP',
        () => _gameProvider.awardXP(XPEvent.lessonComplete),
      ),
      _runSideEffect(
        'earn lesson-complete gems',
        () => _gemsProvider.earnGems(GemEvent.lessonComplete),
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
          () => _gemsProvider.earnGems(GemEvent.perfectLesson),
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

    await _runSideEffect('check lesson milestones', () async {
      final userData = await _gameProvider.getUserGameStateOnce();
      await _achievementsProvider.checkLessonMilestones(
        lessonsCompleted: userData.lessonsCompleted,
        perfectLessons: userData.perfectLessons,
      );
    });

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
      );
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
