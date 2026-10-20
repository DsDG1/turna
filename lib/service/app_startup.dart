// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/practice/ai_practice_job_queue.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_startup_recovery.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/courses/languages/expressions.dart';
import 'package:turna/courses/languages/grammar_points.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/audio/anki_audio_resolver.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/service/local_reminder_service.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/tts_availability_checker.dart';

bool _startupRunning = false;

/// Splash copy for the post-frame seed. Database open/migrate stays before
/// [runApp] so a failed migrate can swap the handle before anything reads it.
enum TurnaStartupPhase { pending, seeding, validating, ready, failed }

class TurnaStartupProgress extends ChangeNotifier {
  TurnaStartupPhase phase = TurnaStartupPhase.pending;

  void update(TurnaStartupPhase next) {
    if (phase == next) return;
    phase = next;
    notifyListeners();
  }
}

final TurnaStartupProgress turnaStartupProgress = TurnaStartupProgress();

/// Finishes seeding and the first course load after the splash can paint.
///
/// [retrySeed] replaces a failed seed gate so a splash retry is not stuck
/// on the same future. Later steps ([CourseProvider.load]) stay idempotent.
Future<void> continueTurnaStartup({bool retrySeed = false}) async {
  if (_startupRunning) return;
  _startupRunning = true;
  turnaStartupProgress.update(TurnaStartupPhase.seeding);
  try {
    if (retrySeed) {
      if (getIt.isRegistered<CourseProvider>()) {
        getIt<CourseProvider>().clearBootFailure();
      }
      retryCourseDatabaseReady();
    }
    await ensureCourseDatabaseReady();
    turnaStartupProgress.update(TurnaStartupPhase.validating);
    await _hydrateAfterSeed();
    if (getIt.isRegistered<CourseProvider>()) {
      getIt<CourseProvider>().clearBootFailure();
    }
    turnaStartupProgress.update(TurnaStartupPhase.ready);
  } catch (e, st) {
    logger.e(
      'Startup continuation failed; splash stays until retry',
      error: e,
      stackTrace: st,
    );
    turnaStartupProgress.update(TurnaStartupPhase.failed);
    if (getIt.isRegistered<CourseProvider>()) {
      getIt<CourseProvider>().reportBootFailure();
    }
  } finally {
    _startupRunning = false;
  }
}

Future<void> _hydrateAfterSeed() async {
  await getIt<AiEngineConfigHolder>().loadPersisted();

  // Must happen here, before `ready`, and not only from HomePage.initSession:
  // the splash gate is `game.initialized && course.isLoaded`, and
  // `ensureUserGameFields` is the only writer of that flag. When the only
  // caller was HomePage, a profile with no prefs — fresh install, cleared
  // data, a cloud-test device — could never open the gate it was itself
  // waiting on: the splash sat on the spinner with no status label (the label
  // is suppressed once the course is loaded) and never navigated. Observed on
  // device 2026-10-20 as "app failed to start". Idempotent for profiles that
  // already carry the flag.
  await getIt<GameProvider>().ensureUserGameFields();

  final persistedScope = CourseScopeCodec.decode(
    getIt<AppPrefs>().courseScope.getValue(),
  );
  final preheatLanguage =
      persistedScope is BuiltinCourseScope ? persistedScope.languageCode : null;
  await loadVocabulary(preheatLanguage);
  await loadGrammarPoints(preheatLanguage);
  await loadExpressions(preheatLanguage);

  final srsLanguage = preheatLanguage ?? LanguageRegistry.instance.defaultCode;
  await getIt<SrsProvider>().setLanguageFilter(srsLanguage);
  await getIt<GrammarReviewProvider>().setLanguageFilter(srsLanguage);

  await OfficialAnkiCompositionRoot.initializeReadOnlyLocator();
  await getIt<CourseProvider>().load();

  // AI practice library: rewrite jobs whose process died as interrupted, apply
  // the retention policy, and hydrate the in-memory list. Deferred off the
  // startup critical path — the hub also retries `ensureLoaded()` on open.
  unawaited(() async {
    try {
      await getIt<AiPracticeJobQueue>().restoreOnStartup();
    } catch (e) {
      logger.d('[AiPractice] startup restore skipped: $e');
    }
  }());

  unawaited(() async {
    try {
      await getIt<AchievementService>().initialize();
    } catch (e) {
      logger.d('[Achievements] startup initialize skipped: $e');
    }
  }());

  unawaited(() async {
    try {
      await const OfficialAnkiStartupRecovery().run();
    } catch (e) {
      logger.d('[OfficialAnki] startup recovery skipped: $e');
    }
  }());

  unawaited(() async {
    try {
      final importDao = AnkiImportDao(getIt<CourseDatabase>());
      final swept = await AnkiAudioResolver().sweepOrphanMedia(
        (importId) async => await importDao.getById(importId) != null,
        sourceHashForImport: (importId) async =>
            (await importDao.getById(importId))?.sourceHash,
      );
      if (swept > 0) {
        logger.d('[AnkiMedia] swept $swept orphan media dir(s)');
      }
    } catch (e) {
      logger.d('[AnkiMedia] orphan sweep skipped: $e');
    }
  }());

  if (!kIsWeb) {
    await getIt<TtsAvailabilityChecker>().configureSystemEngine();
    try {
      final settings = getIt<SettingsProvider>();
      await getIt<LocalReminderService>().applyFromSettings(
        enabled: settings.dailyReminderEnabled,
        time: settings.dailyReminderTime,
      );
    } catch (_) {/* best-effort */}
  }
}
