// Flutter imports:
import 'dart:io';

import 'package:flutter/foundation.dart';

// Package imports:
import 'package:drift/native.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_saved_explanations.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_sqlite.dart';
import 'package:turna/application/settings/commands/apply_fsrs_parameters_command.dart';
import 'package:turna/application/settings/commands/clear_regenerable_caches_command.dart';
import 'package:turna/application/settings/commands/reset_account_command.dart';
import 'package:turna/application/settings/commands/reset_learning_settings_command.dart';
import 'package:turna/application/settings/commands/update_daily_reminder_command.dart';
import 'package:turna/application/restore_normalization_service.dart';
import 'package:turna/application/system_health_monitor.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/verbose.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/course_scope_migration.dart';
import 'package:turna/data/anki_legacy_write_fence.dart';
import 'package:turna/data/anki_owner_authority_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_database_seeder.dart';
import 'package:turna/domain/repositories/i_credential_store.dart';
import 'package:turna/service/secure_credential_store.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/service/export_service.dart';
import 'package:turna/service/remote_backup/backup_snapshot_service.dart';
import 'package:turna/service/remote_backup/remote_backup_config.dart';
import 'package:turna/service/remote_backup/remote_backup_service.dart';
import 'package:turna/service/remote_backup/restore_applier.dart';
import 'package:turna/service/remote_backup/webdav_client.dart';
import 'package:turna/service/remote_backup/webdav_remote_backup_store.dart';
import 'package:turna/service/tab_router.dart';

class AppPrefs {
  final StreamingSharedPreferences preferences;

  AppPrefs(
    this.preferences,
  )   : currentLanguage = preferences.getString(
          PrefsConstants.currentLanguage,
          defaultValue: "turkish",
        ),
        authUser = preferences.getCustomValue(
          PrefsConstants.authUser,
          defaultValue: LocalUser.local,
          adapter: const JsonAdapter(
            serializer: _serializeUser,
            deserializer: _deserializeUser,
          ),
        ),
        courseScope = preferences.getString(
          PrefsConstants.courseScope,
          defaultValue: '',
        );

  final Preference<LocalUser> authUser;
  final Preference<String> currentLanguage;

  /// Active course scope: '' = built-in course, `anki:<importId>` = one
  /// imported Anki deck. See [CourseProvider.courseScope].
  final Preference<String> courseScope;

  Future<bool> setBool(String key, {required bool value}) async {
    printBefore(value: value, key: key);
    return preferences.setBool(key, value);
  }

  Future<bool> setDouble(String key, double value) async {
    printBefore(value: value, key: key);
    return preferences.setDouble(key, value);
  }

  Future<bool> setInt(String key, int value) async {
    printBefore(value: value, key: key);
    return preferences.setInt(key, value);
  }

  Future<bool> setString(String key, String value) async {
    printBefore(value: value, key: key);
    return preferences.setString(key, value);
  }

  Future<bool> setStringList(String key, List<String> value) async {
    printBefore(value: value, key: key);
    return preferences.setStringList(key, value);
  }

  Future<bool> setCustomValue(
      String key, value, PreferenceAdapter<dynamic> adapter) async {
    printBefore(value: value, key: key);
    return preferences.setCustomValue(key, value, adapter: adapter);
  }

  Future<bool> setLocalUser(LocalUser user) async {
    return preferences.setCustomValue(
      PrefsConstants.authUser,
      user.toJson(),
      adapter: const JsonAdapter(),
    );
  }

  void printBefore({String? key, value}) {
    if (!kDebugMode) return;
    // Default: log only the key to cut noise and avoid dumping values into
    // debug logs (potential data leakage). The full value is emitted only
    // under the second-level [Very.verbose] debug switch.
    if (veryVerbose) {
      logger.d('Saving Key: $key &  value: $value');
    } else {
      logger.d('Saving Key: $key');
    }
  }
}

class PrefsConstants {
  static const String authUser = 'authUser';
  static const String currentLanguage = 'currentLanguage';
  static const String courseScope = 'courseScope';

  /// Persisted course order for the course-management page: a list of course
  /// scopes ('' = built-in course, `anki:<importId>` = one deck).
  static const String courseOrder = 'courseOrder';
}

/// Local user state keys — single source of truth for all game progression.
class LocalStateKeys {
  // Marker: true after [GameProvider.ensureUserGameFields] has seeded defaults.
  static const String initialized = 'game.initialized';

  // Game state
  static const String score = 'game.score';
  static const String streak = 'game.streak';
  static const String lastStreakDate = 'game.lastStreakDate';
  // Legacy aggregate counters — kept for back-compat with any consumer that
  // still reads them, but new code should use [completedLessonIds] and
  // [perfectLessonIds] (which are now the source of truth).
  static const String lessonsCompleted = 'game.lessonsCompleted';
  static const String perfectLessons = 'game.perfectLessons';

  // Per-lesson progress — set of completed / perfect lesson ids. The
  // authoritative record. New code must read from these.
  static const String completedLessonIds = 'progress.completedLessonIds';
  static const String perfectLessonIds = 'progress.perfectLessonIds';
  static const String streakWasBroken = 'game.streakWasBroken';
  static const String streakProtectedDays = 'streak.protectedDays';
  static const String streakAutoUseVoucher = 'streak.autoUseVoucher';
  static const String wordsLearned = 'game.wordsLearned';

  // Currency
  static const String gems = 'currency.gems';

  // Cosmetics (gem-spend avatar rings, etc.)
  /// Unlocked cosmetic ids (string list). [ring_mist] is always free.
  static const String cosmeticsUnlocked = 'cosmetics.unlocked';

  /// Currently equipped avatar ring id. Default: [ring_mist].
  static const String cosmeticsEquippedRing = 'cosmetics.equippedRing';

  /// Slot-based equipment keys. The old ring key above remains migration
  /// input only after [cosmetics.equipped.avatarRing] has been written.
  static const String cosmeticsEquippedAvatarRing =
      'cosmetics.equipped.avatarRing';
  static const String cosmeticsEquippedProfileTheme =
      'cosmetics.equipped.profileTheme';
  static const String cosmeticsEquippedCardBack = 'cosmetics.equipped.cardBack';
  static const String cosmeticsEquippedCompletionEffect =
      'cosmetics.equipped.completionEffect';
  static const String cosmeticsEquippedSoundPack =
      'cosmetics.equipped.soundPack';
  static const String cosmeticsEquippedMascotAccessory =
      'cosmetics.equipped.mascotAccessory';

  // Achievements
  /// v1 unlocked-id list. Read-only migration input for the v2 achievement
  /// system — no production code may write to it anymore.
  static const String achievements = 'achievements.unlocked';

  // Achievements v2 (成就系统焕新) — single versioned state document,
  // persistent metric projection, and one-shot migration marker. See
  // docs/achievement-system-revamp-plan.md.
  static const String achievementsStateV2 = 'achievements.state.v2';
  static const String achievementsProjectionV1 =
      'achievements.metric_projection.v1';
  static const String achievementsMigrationVersion =
      'achievements.migration.version';

  // SRS — JSON-serialized Map<String, SrsWord> keyed by wordId.
  static const String srsState = 'srs.state';

  /// Target retention for FSRS (0.80–0.95). Binary scoring only; no grade UI.
  static const String srsDesiredRetention = 'srs.desiredRetention';

  /// JSON list of 21 FSRS weights; empty = package defaults.
  static const String srsFsrsParameters = 'srs.fsrsParameters';

  /// ISO timestamp of last successful local weight fit (empty if never).
  static const String srsFsrsOptimizedAt = 'srs.fsrsOptimizedAt';

  /// Review sample count used in last successful optimization.
  static const String srsFsrsOptimizedReviews = 'srs.fsrsOptimizedReviews';

  // Lesson word links — JSON-serialized Map<String, LessonWordLink> keyed by
  // wordId / grammarPointId (disambiguated by LinkType).
  static const String lessonWordLinks = 'srs.lessonWordLinks';

  // Grammar review SRS — JSON-serialized Map<String, SrsWord> keyed by
  // grammarPointId. Separate queue from [srsState].
  static const String grammarReviewState = 'grammarReview.state';

  // Mistake log — JSON-serialized List<MistakeEntry>.
  static const String mistakeLog = 'mistake.log';

  // Settings
  static const String themeMode =
      'settings.themeMode'; // 'light' | 'dark' | 'system'
  static const String soundEffects = 'settings.soundEffects';
  static const String haptic = 'settings.haptic';
  static const String ttsSpeed = 'settings.ttsSpeed';
  // Legacy: 'settings.ttsEngine' selected the bundled Piper offline model in
  // the Swahili build. Turkish uses system/Google TTS only, so the engine
  // toggle was removed; the key is retained for back-compat reads.
  static const String ttsEngine = 'settings.ttsEngine';
  static const String ttsAvailabilityPromptShown =
      'settings.ttsAvailabilityPromptShown';

  // Daily local reminder (Phase 22)
  static const String dailyReminderEnabled = 'settings.dailyReminderEnabled';
  static const String dailyReminderHour = 'settings.dailyReminderHour';
  static const String dailyReminderMinute = 'settings.dailyReminderMinute';

  // AI engine config (JSON): preset, API key, models, strictSchema, cache.
  // Persisted so the user's AI setup (including the key) survives an app
  // restart. Written through the raw StreamingSharedPreferences to avoid
  // logging the secret (see AiEngineConfigHolder._persist).
  static const String aiEngineConfig = 'ai.engineConfig';

  /// Completion marker for the AI key plaintext->secure-store migration
  /// (Plan 2 S2-M03/M04). Written only after the secure copy is verified.
  static const String aiCredentialMigrated = 'ai.credentialMigrated';

  // Screen auto-rotation: false (default) = lock portrait, true = follow device.
  static const String autoRotate = 'settings.autoRotate';

  // Per-course smart-TTS settings, keyed by course scope ('' = built-in
  // course, 'anki:<importId>' = imported deck). See SettingsProvider.
  // autoReadOnTap: whether tapping an option / revealing a card auto-reads it.
  // nativeLang: BCP-47 base code of the translation/native language, used as
  // the TTS fallback voice for plain-Latin text.
  static String autoReadOnTapKey(String scope) =>
      'settings.autoReadOnTap.${scope.isEmpty ? 'builtin' : scope}';
  static String nativeLanguageKey(String scope) =>
      'settings.nativeLang.${scope.isEmpty ? 'builtin' : scope}';

  static const String ankiPreRenderEnabled = 'anki.preRenderEnabled';
  static const String ankiCaptureDelaySec = 'anki.captureDelaySec';
  static const String ankiLiteThreshold = 'anki.liteThreshold';
  static const String ankiForceDisableJs = 'anki.forceDisableJs';
  static const String systemHealthEvent = 'system.healthEvent';

  // Accessibility / neurodiversity settings — see AccessibilityProvider.
  // textScale is an int percent (100 = 1.0, 200 = 2.0); the rest are bool flags.
  static const String textScale = 'settings.textScale';
  static const String reducedMotion = 'settings.reducedMotion';
  static const String highContrast = 'settings.highContrast';
  static const String dyslexiaFont = 'settings.dyslexiaFont';
  static const String sensoryReduce = 'settings.sensoryReduce';
  static const String focusMode = 'settings.focusMode';

  /// Last content version the user acknowledged via the content-update dialog
  /// (ADR 0002). When the bundled course content version changes and the user
  /// has existing progress, the dialog is shown; on dismissal (keep or reset)
  /// this is set to the current content version so it does not reappear.
  static const String contentVersionAcknowledged = 'contentUpdate.acknowledged';

  // UI display locale (app interface language): 'en' | 'zh' | 'system'.
  static const String uiLocale = 'settings.uiLocale';

  // Fun / cheat settings — see FunProvider.
  static const String funAutoAnswer = 'fun.autoAnswer';
  static const String funAllAchievementsUnlocked =
      'fun.allAchievementsUnlocked';

  // Remote backup (WebDAV) — config contains the password, so it is written
  // through the raw StreamingSharedPreferences to bypass printBefore (same
  // approach as [aiEngineConfig]). These keys are device-local and never
  // included in backup payloads.
  static const String remoteBackupConfig = 'remoteBackup.config';
  static const String remoteBackupDeviceId = 'remoteBackup.deviceId';
  static const String remoteBackupLastInfo = 'remoteBackup.lastBackupInfo';
  static const String remoteBackupLastRestoredAt =
      'remoteBackup.lastRestoredAt';
  static const String remoteBackupRestoreBlockedReason =
      'remoteBackup.restoreBlockedReason';
  static const String remoteBackupNormalizationPending =
      'remoteBackup.normalizationPending';
}

/// Making AppPrefs injectable
Future<void> setupLocator() async {
  final preferences = await StreamingSharedPreferences.instance;
  getIt.registerLazySingleton<AppPrefs>(() => AppPrefs(preferences));

  // Bottom-nav tab switcher — registered early so HomePage and any pushed
  // route (e.g. lesson dialog) can resolve it synchronously.
  getIt.registerLazySingleton<TabRouter>(() => TabRouter());

  // Platform secure credential storage (AI API key, WebDAV password). Falls
  // back to a session-only in-memory store when the platform plugin is
  // unavailable; isPersistent tells consumers which one they got.
  if (!getIt.isRegistered<ICredentialStore>()) {
    getIt.registerLazySingleton<ICredentialStore>(
      () => SecureCredentialStore(),
    );
  }

  // Move a legacy plaintext WebDAV password (old releases stored it inside
  // the prefs JSON) into the secure store. Idempotent; on any failure the
  // plaintext is kept and the migration retries on the next boot.
  if (!kIsWeb) {
    final migrationStatus = await RemoteBackupConfigStore(getIt<AppPrefs>())
        .migrateLegacyPlaintext();
    if (migrationStatus != RemoteBackupCredentialMigrationStatus.notNeeded &&
        migrationStatus != RemoteBackupCredentialMigrationStatus.migrated) {
      logger.w('WebDAV credential migration deferred: $migrationStatus');
    }
  }

  if (!getIt.isRegistered<SystemHealthMonitor>()) {
    getIt.registerLazySingleton<SystemHealthMonitor>(
      () => SystemHealthMonitor(getIt<AppPrefs>()),
    );
  }

  // Cross-service settings operations run through command coordinators so
  // widgets never orchestrate multi-service side effects themselves.
  if (!getIt.isRegistered<UpdateDailyReminderCommand>()) {
    getIt.registerLazySingleton<UpdateDailyReminderCommand>(
        () => UpdateDailyReminderCommand());
  }
  if (!getIt.isRegistered<ResetLearningSettingsCommand>()) {
    getIt.registerLazySingleton<ResetLearningSettingsCommand>(
        () => ResetLearningSettingsCommand());
  }
  if (!getIt.isRegistered<ResetAccountCommand>()) {
    getIt.registerLazySingleton<ResetAccountCommand>(
        () => ResetAccountCommand());
  }
  if (!getIt.isRegistered<ApplyFsrsParametersCommand>()) {
    getIt.registerLazySingleton<ApplyFsrsParametersCommand>(
        () => ApplyFsrsParametersCommand());
  }
  if (!getIt.isRegistered<ClearRegenerableCachesCommand>()) {
    getIt.registerLazySingleton<ClearRegenerableCachesCommand>(
        () => ClearRegenerableCachesCommand());
  }

  getIt.registerLazySingleton<ExportService>(
      () => ExportService(getIt<AppPrefs>()));

  // Companion stores — single instances for all AI surfaces (hardens against
  // orphan prefs that ignore settings UI changes).
  if (!getIt.isRegistered<AiExplainPrefsStore>()) {
    getIt.registerLazySingleton<AiExplainPrefsStore>(
        () => AiExplainPrefsStore());
  }
  if (!getIt.isRegistered<AiSavedExplanationsStore>()) {
    getIt.registerLazySingleton<AiSavedExplanationsStore>(
        () => AiSavedExplanationsStore());
  }

  if (!kIsWeb) {
    getIt.registerLazySingleton<FlutterTts>(() => FlutterTts());
  }

  // Open + seed the course database before any course read. First install /
  // content-version bump reseeds; subsequent cold starts skip when version
  // matches and sections exist. Registered as a singleton so [CourseLoader]
  // can resolve it synchronously.
  //
  // Non-web platforms use sqlite3 FFI (NativeDatabase). Apply a staged
  // remote restore (armed from the remote-backup settings page) before any
  // database or the official Anki engine opens — this is the only point in
  // the boot sequence where every data file is closed. Web has no local DBs.
  var remoteRestoreApplied = false;
  if (!kIsWeb) {
    final appSupport = await getApplicationSupportDirectory();
    final outcome = await RestoreApplier(
      prefs: getIt<AppPrefs>(),
      appSupport: appSupport,
      appDocuments: await getApplicationDocumentsDirectory(),
      officialProfileRoot:
          Directory(p.join(appSupport.path, 'official_anki', 'default')),
      currentDriftSchema: CourseDatabase.kSchemaVersion,
      currentCatalogSchema: kOfficialAnkiCatalogSchemaVersion,
    ).applyIfPending();
    if (outcome != RestoreApplyOutcome.noPending) {
      logger.i('Remote restore boot outcome: $outcome');
    }
    remoteRestoreApplied = outcome == RestoreApplyOutcome.applied;
  }

  final db = await _openAndSeedCourseDatabase();
  getIt.registerSingleton<CourseDatabase>(db);
  getIt.registerSingleton(AnkiUnificationDao(db));
  getIt.registerSingleton(AnkiOwnerAuthorityDao(db));
  getIt.registerSingleton(
      CardIntroductionStore(dao: getIt<AnkiUnificationDao>()));
  // Cold-start hydration (01-due-state.md): the store is write-through
  // only, so without this pass every formal-due query after a restart sees
  // an empty introduced set and filters out every due card.
  await getIt<CardIntroductionStore>().hydrateFromLedger();

  // Course-scope preference repair (plan 34 §6.4): must run after the DB and
  // source catalog are open and BEFORE CourseProvider reads the preference.
  // Idempotent; journals one row per actual change.
  try {
    await CourseScopePreferenceMigrator.repair(courseDb: db);
  } catch (e) {
    logger.w('course scope preference repair skipped: $e');
  }

  // Load the Legacy write fences (plan 34 §R4-1) before any Legacy writer
  // can run.
  try {
    await LegacyWriteFence.instance.loadFrom(db);
  } catch (e) {
    logger.w('legacy write fence load skipped: $e');
  }

  if (!getIt.isRegistered<RestoreNormalizationService>()) {
    getIt.registerLazySingleton<RestoreNormalizationService>(
      () => RestoreNormalizationService(
        prefs: getIt<AppPrefs>(),
        gems: getIt(),
        cosmetics: getIt(),
        aiConfig: getIt(),
      ),
    );
  }
  final normalizationPending = remoteRestoreApplied ||
      getIt<AppPrefs>()
          .preferences
          .getBool(
            LocalStateKeys.remoteBackupNormalizationPending,
            defaultValue: false,
          )
          .getValue();
  if (normalizationPending) {
    await getIt<RestoreNormalizationService>().normalize();
    await getIt<AppPrefs>()
        .preferences
        .remove(LocalStateKeys.remoteBackupNormalizationPending);
  }

  // Remote backup (manual WebDAV backup / restore) — needs file-backed DBs.
  if (!kIsWeb) {
    final appSupport = await getApplicationSupportDirectory();
    if (!getIt.isRegistered<PackageInfo>()) {
      getIt.registerSingleton<PackageInfo>(await PackageInfo.fromPlatform());
    }
    if (!getIt.isRegistered<RemoteBackupConfigStore>()) {
      getIt.registerLazySingleton<RemoteBackupConfigStore>(
          () => RemoteBackupConfigStore(getIt<AppPrefs>()));
    }
    if (!getIt.isRegistered<BackupSnapshotService>()) {
      getIt.registerLazySingleton<BackupSnapshotService>(
          () => BackupSnapshotService(
                db: getIt<CourseDatabase>(),
                packageInfo: getIt<PackageInfo>(),
              ));
    }
    if (!getIt.isRegistered<RemoteBackupService>()) {
      getIt.registerLazySingleton<RemoteBackupService>(() {
        final configStore = getIt<RemoteBackupConfigStore>();
        return RemoteBackupService(
          prefs: getIt<AppPrefs>(),
          configStore: configStore,
          snapshotService: getIt<BackupSnapshotService>(),
          appSupport: appSupport,
          storeFactory: (config) => WebDavRemoteBackupStore(
            WebDavClient.fromConfig(config),
            remoteRoot: config.normalized().remoteRoot,
          ),
        );
      });
    }
  }

  // NOTE: the vocabulary / grammar / expression pre-loads
  // (loadVocabulary / loadGrammarPoints / loadExpressions)
  // are deferred to a post-frame callback in main.dart so runApp can paint the
  // splash immediately instead of blocking on the full table read. They are
  // idempotent one-shot loads and finish before the course tree shows lessons.
}

/// Opens the on-device course database and seeds it from the bundled JSON
/// assets when needed (version / empty-tree gate).
///
/// Non-web platforms use [NativeDatabase] (sqlite3 FFI). Web is unsupported.
Future<CourseDatabase> _openAndSeedCourseDatabase() async {
  final CourseDatabase db;

  if (kIsWeb) {
    throw UnsupportedError(
      'CourseDatabase is not supported on web yet (NativeDatabase requires '
      'native sqlite3).',
    );
  }

  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'course.db'));
  // SQL runs on a dedicated background isolate so large imports (Anki deck
  // assembly, SRS migration) never occupy the UI thread — every awaited
  // statement becomes a real suspension point and progress UI keeps
  // rendering. [ensureOfficialAnkiSqlite] resolves the native sqlite3
  // library inside that isolate (open.overrideFor is per-isolate state).
  db = CourseDatabase(
    NativeDatabase.createInBackground(
      file,
      isolateSetup: ensureOfficialAnkiSqlite,
    ),
  );

  try {
    await DatabaseSeeder(db).seedIfNeeded();
  } catch (e, st) {
    logger.e('Course database seed failed', error: e, stackTrace: st);
    rethrow;
  }
  return db;
}

Map<String, dynamic> _serializeUser(LocalUser user) => user.toJson();

LocalUser _deserializeUser(dynamic value) =>
    LocalUser.fromJson(value as Map<String, dynamic>);
