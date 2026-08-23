// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/lesson_progress_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/srs_queue_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/local_reminder_service.dart';

/// Result of a post-restore runtime reload sweep.
class PostRestoreReloadReport {
  PostRestoreReloadReport({required this.reloaded, required this.failures});

  /// Names of the reload steps that ran successfully, in execution order.
  final List<String> reloaded;

  /// Step name → failure description. A failing step never aborts the
  /// remaining steps — the user gets a partial-success report instead of a
  /// silently half-live app.
  final Map<String, String> failures;

  bool get allSucceeded => failures.isEmpty;
}

/// Single ordered place that refreshes every runtime consumer after a backup
/// restore (local import or remote boot-time apply). Before this existed the
/// local import path reloaded only AchievementService and let everything else
/// wait for an app restart, so restored values were invisible or stale.
///
/// Step order matters: prefs-backed providers first (they re-read prefs),
/// then services that re-apply side effects (audio, reminders), then derived
/// aggregators (SRS queue, achievements, stats). Steps are guarded by
/// `isRegistered` so the registry also runs in tests with a partial app
/// graph, and a step failure is captured instead of thrown.
class PostRestoreReloadRegistry {
  final List<(_ReloadStep step, bool Function() available)> _steps = [];

  void register(String name, Future<void> Function() action) {
    _steps.add((_ReloadStep(name, action), () => true));
  }

  void _registerIf(
    String name,
    bool Function() available,
    Future<void> Function() action,
  ) {
    _steps.add((_ReloadStep(name, action), available));
  }

  static PostRestoreReloadRegistry withDefaultSteps() {
    final registry = PostRestoreReloadRegistry().._addDefaultSteps();
    return registry;
  }

  void _addDefaultSteps() {
    // ── settings / theme / language ──
    _registerIf(
      'settings',
      () => getIt.isRegistered<SettingsProvider>(),
      () async => getIt<SettingsProvider>().reload(),
    );
    _registerIf(
      'accessibility',
      () => getIt.isRegistered<AccessibilityProvider>(),
      () async => getIt<AccessibilityProvider>().reload(),
    );
    _registerIf(
      'language',
      () => getIt.isRegistered<LanguageProvider>(),
      () async => getIt<LanguageProvider>().initLanguage(),
    );

    // ── audio + reminders (side-effect services) ──
    _registerIf(
      'audio',
      () =>
          getIt.isRegistered<AudioController>() &&
          getIt.isRegistered<SettingsProvider>(),
      () async => getIt<AudioController>()
          .setTtsSpeed(getIt<SettingsProvider>().ttsSpeed),
    );
    _registerIf(
      'reminder',
      () =>
          getIt.isRegistered<LocalReminderService>() &&
          getIt.isRegistered<SettingsProvider>(),
      () async => getIt<LocalReminderService>().applyFromSettings(
        enabled: getIt<SettingsProvider>().dailyReminderEnabled,
        time: getIt<SettingsProvider>().dailyReminderTime,
      ),
    );

    // ── gamification state ──
    _registerIf(
      'game',
      () => getIt.isRegistered<GameProvider>(),
      () async => getIt<GameProvider>().refreshFromPrefs(),
    );
    _registerIf(
      'gems',
      () => getIt.isRegistered<GemsProvider>(),
      () async => getIt<GemsProvider>().refreshFromPrefs(),
    );
    _registerIf(
      'cosmetics',
      () => getIt.isRegistered<CosmeticProvider>(),
      () async => getIt<CosmeticProvider>().refreshFromPrefs(),
    );

    // ── learning state ──
    _registerIf(
      'srs',
      () => getIt.isRegistered<SrsProvider>(),
      () async => getIt<SrsProvider>().reloadFromStorage(),
    );
    _registerIf(
      'grammarReview',
      () => getIt.isRegistered<GrammarReviewProvider>(),
      () async => getIt<GrammarReviewProvider>().reloadFromStorage(),
    );
    _registerIf(
      'mistakes',
      () => getIt.isRegistered<MistakeProvider>(),
      () async => getIt<MistakeProvider>().reloadFromPrefs(),
    );
    _registerIf(
      'lessonProgress',
      () => getIt.isRegistered<LessonProgressProvider>(),
      () async => getIt<LessonProgressProvider>().reloadFromPrefs(),
    );
    _registerIf(
      'studyLogs',
      () => getIt.isRegistered<StudyLogRepository>(),
      () async => getIt<StudyLogRepository>().reloadFromPrefs(),
    );
    _registerIf(
      'studyStats',
      () => getIt.isRegistered<StudyStatsProvider>(),
      () async => getIt<StudyStatsProvider>().refreshFromPrefs(),
    );

    // ── derived aggregates ──
    _registerIf(
      'achievements',
      () => getIt.isRegistered<AchievementService>(),
      () async => getIt<AchievementService>().reloadFromPrefs(),
    );
    _registerIf(
      'srsQueue',
      () => getIt.isRegistered<SrsQueueProvider>(),
      () async => getIt<SrsQueueProvider>().reloadFromStorage(),
    );

    // ── AI non-sensitive config ──
    _registerIf(
      'aiPrefs',
      () => getIt.isRegistered<AiExplainPrefsStore>(),
      () async => getIt<AiExplainPrefsStore>().load(),
    );
  }

  /// Runs every registered step in order. Never throws: step failures are
  /// captured into the report.
  Future<PostRestoreReloadReport> reloadAll() async {
    final reloaded = <String>[];
    final failures = <String, String>{};
    for (final (step, available) in _steps) {
      bool registered;
      try {
        registered = available();
      } catch (_) {
        registered = false;
      }
      if (!registered) continue;
      try {
        await step.action();
        reloaded.add(step.name);
      } catch (error) {
        if (kDebugMode) {
          debugPrint('PostRestoreReload step "${step.name}" failed: $error');
        }
        failures[step.name] = error.toString();
      }
    }
    return PostRestoreReloadReport(reloaded: reloaded, failures: failures);
  }
}

class _ReloadStep {
  const _ReloadStep(this.name, this.action);

  final String name;
  final Future<void> Function() action;
}
