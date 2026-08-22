// Test helper: builds a real achievement v2 stack (repository, projector,
// migration, service) on top of mock prefs, mirroring the DI wiring.

import 'package:turna/application/achievements/achievement_metric_projector.dart';
import 'package:turna/application/achievements/achievement_migration_service.dart';
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/achievements/achievement_state_repository.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/lesson_progress_provider.dart';
import 'package:turna/application/score_provider.dart';
import 'package:turna/application/streak_provider.dart';
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/service/locator.dart';

class AchievementTestStack {
  final AchievementStateRepository stateRepository;
  final AchievementMetricProjector projector;
  final AchievementMigrationService migrationService;
  final GemsProvider gemsProvider;
  final AchievementService service;
  final LessonProgressProvider lessonProgress;

  AchievementTestStack._(
    this.stateRepository,
    this.projector,
    this.migrationService,
    this.gemsProvider,
    this.service,
    this.lessonProgress,
  );

  static AchievementTestStack build(AppPrefs prefs) {
    final lessonProgress = LessonProgressProvider(prefs);
    final stateRepository = AchievementStateRepository(prefs);
    final projector = AchievementMetricProjector(
      prefs,
      lessonProgress,
      StreakProvider(prefs),
      ScoreProvider(prefs),
      StudyLogRepository(prefs),
    );
    final migrationService = AchievementMigrationService(
      prefs,
      stateRepository,
      projector,
    );
    final gemsProvider = GemsProvider(prefs);
    final service = AchievementService(
      stateRepository,
      projector,
      migrationService,
      gemsProvider,
    );
    return AchievementTestStack._(
      stateRepository,
      projector,
      migrationService,
      gemsProvider,
      service,
      lessonProgress,
    );
  }
}
