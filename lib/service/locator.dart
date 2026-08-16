// Flutter imports:
import 'dart:io';

import 'package:flutter/foundation.dart';

// Package imports:
import 'package:drift/native.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_saved_explanations.dart';
import 'package:turna/application/system_health_monitor.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/verbose.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_database_seeder.dart';
import 'package:turna/data/rdb_query_executor.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/service/export_service.dart';
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

  /// Active course scope: '' = built-in course, 'anki:<importId>' = one
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
  /// scopes ('' = built-in course, 'anki:<importId>' = one deck).
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
  static const String wordsLearned = 'game.wordsLearned';

  // Currency
  static const String gems = 'currency.gems';

  // Cosmetics (gem-spend avatar rings, etc.)
  /// Unlocked cosmetic ids (string list). [ring_mist] is always free.
  static const String cosmeticsUnlocked = 'cosmetics.unlocked';

  /// Currently equipped avatar ring id. Default: [ring_mist].
  static const String cosmeticsEquippedRing = 'cosmetics.equippedRing';

  // Achievements
  static const String achievements = 'achievements.unlocked';

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
}

/// Making AppPrefs injectable
Future<void> setupLocator() async {
  final preferences = await StreamingSharedPreferences.instance;
  getIt.registerLazySingleton<AppPrefs>(() => AppPrefs(preferences));

  // Bottom-nav tab switcher — registered early so HomePage and any pushed
  // route (e.g. lesson dialog) can resolve it synchronously.
  getIt.registerLazySingleton<TabRouter>(() => TabRouter());

  if (!getIt.isRegistered<SystemHealthMonitor>()) {
    getIt.registerLazySingleton<SystemHealthMonitor>(
      () => SystemHealthMonitor(getIt<AppPrefs>()),
    );
  }

  getIt.registerLazySingleton<ExportService>(
      () => ExportService(getIt<AppPrefs>()));

  // Companion stores — single instances for all AI surfaces (hardens against
  // orphan prefs that ignore settings UI changes).
  if (!getIt.isRegistered<AiExplainPrefsStore>()) {
    getIt.registerLazySingleton<AiExplainPrefsStore>(() => AiExplainPrefsStore());
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
  // OHos (HarmonyOS): uses native RDB via MethodChannel bridge
  // (HarmonyOsRdbExecutor). Android/iOS use sqlite3 FFI (NativeDatabase).
  final db = await _openAndSeedCourseDatabase();
  getIt.registerSingleton<CourseDatabase>(db);

  // NOTE: the vocabulary / grammar / expression pre-loads
  // (loadVocabulary / loadGrammarPoints / loadExpressions)
  // are deferred to a post-frame callback in main.dart so runApp can paint the
  // splash immediately instead of blocking on the full table read. They are
  // idempotent one-shot loads and finish before the course tree shows lessons.
}

/// Opens the on-device course database and seeds it from the bundled JSON
/// assets when needed (version / empty-tree gate).
///
/// - OHos: uses [HarmonyOsRdbExecutor] backed by native RDB.
/// - Android/iOS: uses [NativeDatabase] backed by sqlite3 FFI.
/// - Web: not supported (`NativeDatabase` requires native sqlite3).
Future<CourseDatabase> _openAndSeedCourseDatabase() async {
  final CourseDatabase db;

  if (defaultTargetPlatform.name == 'ohos') {
    final executor = HarmonyOsRdbExecutor('course.db');
    db = CourseDatabase(executor);
    await executor.ensureOpen(db);
  } else if (kIsWeb) {
    throw UnsupportedError(
      'CourseDatabase is not supported on web yet (NativeDatabase requires '
      'native sqlite3).',
    );
  } else {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'course.db'));
    db = CourseDatabase(NativeDatabase(file));
  }

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
