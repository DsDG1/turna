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
import 'package:varnamala/core/logger.dart';
import 'package:varnamala/data/course_database.dart';
import 'package:varnamala/data/course_database_seeder.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/auth/local_user.dart';

class AppPrefs {
  final StreamingSharedPreferences preferences;

  AppPrefs(
    this.preferences,
  )   : currentLanguage = preferences.getString(
          PrefsConstants.currentLanguage,
          defaultValue: "swahili",
        ),
        authUser = preferences.getCustomValue(
          PrefsConstants.authUser,
          defaultValue: LocalUser.local,
          adapter: const JsonAdapter(
            serializer: _serializeUser,
            deserializer: _deserializeUser,
          ),
        );

  final Preference<LocalUser> authUser;
  final Preference<String> currentLanguage;

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
    if (kDebugMode) {
      logger.d('Saving Key: $key &  value: $value');
    }
  }
}

class PrefsConstants {
  static const String authUser = 'authUser';
  static const String currentLanguage = 'currentLanguage';
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

  // Achievements
  static const String achievements = 'achievements.unlocked';

  // SRS — JSON-serialized Map<String, SrsWord> keyed by wordId.
  static const String srsState = 'srs.state';

  // Lesson word links — JSON-serialized Map<String, LessonWordLink> keyed by
  // wordId / grammarPointId (disambiguated by LinkType).
  static const String lessonWordLinks = 'srs.lessonWordLinks';

  // Grammar review SRS — JSON-serialized Map<String, SrsWord> keyed by
  // grammarPointId. Separate queue from [srsState].
  static const String grammarReviewState = 'grammarReview.state';

  // Mistake log — JSON-serialized List<MistakeEntry>.
  static const String mistakeLog = 'mistake.log';

  // Settings
  static const String themeMode = 'settings.themeMode'; // 'light' | 'dark' | 'system'
  static const String soundEffects = 'settings.soundEffects';
  static const String haptic = 'settings.haptic';
  static const String ttsSpeed = 'settings.ttsSpeed';
  static const String ttsEngine = 'settings.ttsEngine'; // 'system' | 'offline'
  static const String ttsAvailabilityPromptShown =
      'settings.ttsAvailabilityPromptShown';
}

/// Making AppPrefs injectable
Future<void> setupLocator() async {
  final preferences = await StreamingSharedPreferences.instance;
  getIt.registerLazySingleton<AppPrefs>(() => AppPrefs(preferences));

  if (!kIsWeb) {
    getIt.registerLazySingleton<FlutterTts>(() => FlutterTts());
  }

  // Open + seed the course database before any course read. First install /
  // content-version bump reseeds; subsequent cold starts skip when version
  // matches and sections exist. Registered as a singleton so [SwahiliCourse]
  // can resolve it synchronously.
  final db = await _openAndSeedCourseDatabase();
  getIt.registerSingleton<CourseDatabase>(db);

  // NOTE: the Swahili vocabulary / grammar / expression pre-loads
  // (loadSwahiliVocabulary / loadSwahiliGrammarPoints / loadSwahiliExpressions)
  // are deferred to a post-frame callback in main.dart so runApp can paint the
  // splash immediately instead of blocking on the full table read. They are
  // idempotent one-shot loads and finish before the course tree shows lessons.
}

/// Opens the on-device course database and seeds it from the bundled JSON
/// assets when needed (version / empty-tree gate). Not supported on web
/// (`NativeDatabase` needs native `sqlite3`); a future revision can swap in
/// a WASM database for web.
Future<CourseDatabase> _openAndSeedCourseDatabase() async {
  if (kIsWeb) {
    throw UnsupportedError(
      'CourseDatabase is not supported on web yet (NativeDatabase requires '
      'native sqlite3).',
    );
  }
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'course.swahili.db'));
  final db = CourseDatabase(NativeDatabase(file));
  try {
    await DatabaseSeeder(db).seedIfNeeded();
  } catch (e, st) {
    logger.e('Course database seed failed', error: e, stackTrace: st);
    rethrow;
  }
  return db;
}

Map<String, dynamic> _serializeUser(LocalUser user) =>
    user.toJson();

LocalUser _deserializeUser(dynamic value) =>
    LocalUser.fromJson(value as Map<String, dynamic>);
