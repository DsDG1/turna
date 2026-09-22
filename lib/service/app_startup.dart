// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_startup_recovery.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/course_provider.dart';
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

/// Finishes seeding and the first course load after the splash can paint.
///
/// [retrySeed] replaces a failed seed gate so a splash retry is not stuck
/// on the same future. Later steps ([CourseProvider.load]) stay idempotent.
Future<void> continueTurnaStartup({bool retrySeed = false}) async {
  if (_startupRunning) return;
  _startupRunning = true;
  try {
    if (retrySeed) {
      if (getIt.isRegistered<CourseProvider>()) {
        getIt<CourseProvider>().clearBootFailure();
      }
      retryCourseDatabaseReady();
    }
    await ensureCourseDatabaseReady();
    await _hydrateAfterSeed();
    if (getIt.isRegistered<CourseProvider>()) {
      getIt<CourseProvider>().clearBootFailure();
    }
  } catch (e, st) {
    logger.e(
      'Startup continuation failed; splash stays until retry',
      error: e,
      stackTrace: st,
    );
    if (getIt.isRegistered<CourseProvider>()) {
      getIt<CourseProvider>().reportBootFailure();
    }
  } finally {
    _startupRunning = false;
  }
}

Future<void> _hydrateAfterSeed() async {
  await getIt<AiEngineConfigHolder>().loadPersisted();

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
