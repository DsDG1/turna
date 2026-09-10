// Flutter imports:
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:firebase_core/firebase_core.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_startup_recovery.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/courses/languages/expressions.dart';
import 'package:turna/courses/languages/grammar_points.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/core/log_capture.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/audio/anki_audio_resolver.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/firebase_options.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/system_health_monitor.dart';
import 'package:turna/service/local_reminder_service.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/tts_availability_checker.dart';
import 'package:turna/views/app.dart';

/// Install global error handlers so uncaught framework and platform errors
/// are observable in the app log instead of disappearing. This is an offline
/// app, so errors are logged locally only — never sent to a remote backend.
void _installGlobalErrorHandlers() {
  // Framework errors that the Flutter framework would otherwise print to
  // the console in debug and swallow in release.
  FlutterError.onError = (FlutterErrorDetails details) {
    logger.e('Uncaught framework error',
        error: details.exception, stackTrace: details.stack);
    FlutterError.presentError(details);
  };

  // Errors thrown outside the Flutter framework (isolates, async gaps).
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logger.e('Uncaught platform error', error: error, stackTrace: stack);
    return true; // handled: suppress the default crash print.
  };
}

Future<void> main() async {
  // Capture errors as early as possible, before any binding work runs.
  _installGlobalErrorHandlers();

  WidgetsFlutterBinding.ensureInitialized();
  // Firebase is registered for Android (turna-d0d5e) only. Other platforms
  // keep the existing startup path until FlutterFire is re-run for them.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  configureDependencies();

  // AppPrefs (and other async-native services) must be registered before the
  // first frame because MultiProvider creates ThemeProvider immediately.
  await setupLocator();

  // 透明度报告:挂上本地日志捕获,跨重启保留。
  // 必须在 configureDependencies 之后,这样 logger 已是单例;
  // 放在 runApp 之前,确保第一帧之前的早期日志也能进入。
  await LogCapture.instance.install();
  await getIt<SystemHealthMonitor>().install(LogCapture.instance.entries);

  // When companion explain prefs change (language/depth), drop engine cache so
  // stale replies in the wrong language are not replayed.
  AiExplainPrefsStore.onCacheInvalidate = () {
    try {
      getIt<AiEngine>().clearCache();
    } catch (_) {}
  };

  // Lock the app to portrait unless the user has enabled auto-rotation in
  // Settings (default off). Applied before the first frame so the splash is
  // already portrait; the live toggle is handled by _OrientationController.
  await SystemChrome.setPreferredOrientations(
    getIt<SettingsProvider>().autoRotateEnabled
        ? []
        : [DeviceOrientation.portraitUp],
  );

  // Kick off the course load on the first frame instead of blocking before
  // runApp. CourseTree renders its own loading indicator until the shells
  // arrive, so the app paints immediately rather than showing a blank screen
  // during the (cold) DB read. CourseProvider.load() is idempotent, so the
  // CourseTree's defensive ensureSectionLoaded can never double-load or reset
  // shells back to their initial state.
  runApp(const TurnaApp());

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Hydrate the AI engine config (preset + API key + models) from prefs so
    // the user's AI setup survives a restart. Best-effort and fast (a single
    // prefs read); a missing/corrupt record leaves the in-memory default.
    await getIt<AiEngineConfigHolder>().loadPersisted();

    // Populate the synchronous lookup maps (vocab / grammar /
    // expressions) before the course tree shows lessons. Deferred from
    // setupLocator so runApp paints the splash without waiting on the full
    // table read. Idempotent one-shot loads.
    //
    // Preheat the PERSISTED scope's language (prefs are sync-readable now)
    // instead of the manifest's first entry, so a learner whose last course
    // was French never observes Turkish data in the compatibility maps
    // while CourseProvider.load() catches up. Non-builtin/unreadable
    // scopes fall back to the registry default, matching the provider's
    // own _syncPracticeLanguage fallback.
    final persistedScope = CourseScopeCodec.decode(
      getIt<AppPrefs>().courseScope.getValue(),
    );
    final preheatLanguage = persistedScope is BuiltinCourseScope
        ? persistedScope.languageCode
        : null;
    await loadVocabulary(preheatLanguage);
    await loadGrammarPoints(preheatLanguage);
    await loadExpressions(preheatLanguage);

    // Hydrate SRS state from SQLite before any screen reads due counts. This
    // also runs the one-time prefs->SQLite migration (schema v7) on first boot
    // after upgrade. Idempotent. Hydrate under the persisted scope's language
    // (same rationale as the vocabulary preheat above) so due badges don't
    // flash another language's counts before CourseProvider.load() syncs.
    final srsLanguage = preheatLanguage ?? LanguageRegistry.instance.defaultCode;
    await getIt<SrsProvider>().setLanguageFilter(srsLanguage);
    await getIt<GrammarReviewProvider>().setLanguageFilter(srsLanguage);

    await OfficialAnkiCompositionRoot.initializeReadOnlyLocator();
    await getIt<CourseProvider>().load();

    // Achievement system v2 startup: one-shot v1 migration, pending-reward
    // recovery, and a light reconcile against authoritative metrics. Failures
    // defer to the next launch — never block the main flow (plan §12.2).
    unawaited(() async {
      try {
        await getIt<AchievementService>().initialize();
      } catch (e) {
        debugPrint('[Achievements] startup initialize skipped: $e');
      }
    }());

    unawaited(() async {
      try {
        await const OfficialAnkiStartupRecovery().run();
      } catch (e) {
        debugPrint('[OfficialAnki] startup recovery skipped: $e');
      }
    }());

    // Recover an interrupted in-place media swap from its source-hash marker,
    // then retry deletion of owner-less directories whose uninstall left
    // locked files behind (audio player / WebView handles).
    unawaited(() async {
      try {
        final importDao = AnkiImportDao(getIt<CourseDatabase>());
        final swept = await AnkiAudioResolver().sweepOrphanMedia(
          (importId) async => await importDao.getById(importId) != null,
          sourceHashForImport: (importId) async =>
              (await importDao.getById(importId))?.sourceHash,
        );
        if (swept > 0) {
          debugPrint('[AnkiMedia] swept $swept orphan media dir(s)');
        }
      } catch (e) {
        debugPrint('[AnkiMedia] orphan sweep skipped: $e');
      }
    }());

    if (!kIsWeb) {
      // Prefer Google TTS on Android before any speak/availability checks so
      // OEM default engines without Turkish do not shadow the real system
      // voice.
      await getIt<TtsAvailabilityChecker>().configureSystemEngine();

      // Re-arm daily reminder from prefs (best-effort; never block UI).
      try {
        final settings = getIt<SettingsProvider>();
        await getIt<LocalReminderService>().applyFromSettings(
          enabled: settings.dailyReminderEnabled,
          time: settings.dailyReminderTime,
        );
      } catch (_) {/* best-effort */}
    }
  });
}
