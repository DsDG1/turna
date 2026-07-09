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
import 'package:words625/core/logger.dart';
import 'package:words625/courses/languages/expressions.dart';
import 'package:words625/courses/languages/grammar_points.dart';
import 'package:words625/courses/languages/kannada_vocab.dart';
import 'package:words625/data/course_database.dart';
import 'package:words625/data/course_database_seeder.dart';
import 'package:words625/di/injection.dart';
import 'package:words625/domain/auth/local_user.dart';
import 'package:words625/routing/routing.dart';

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
          defaultValue: SerializableFirebaseUser.local,
          adapter: const JsonAdapter(
            serializer: _serializeUser,
            deserializer: _deserializeUser,
          ),
        );

  final Preference<SerializableFirebaseUser> authUser;
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

  Future<bool> setLocalUser(SerializableFirebaseUser user) async {
    return preferences.setCustomValue(
      PrefsConstants.authUser,
      user.toJson(),
      adapter: const JsonAdapter(),
    );
  }

  void printBefore({String? key, value}) =>
      logger.w('Saving Key: $key &  value: $value');
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
  static const String hearts = 'currency.hearts';
  static const String heartsRefillAt = 'currency.heartsRefillAt';

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
}

/// Making AppPrefs injectable
Future<void> setupLocator() async {
  final preferences = await StreamingSharedPreferences.instance;
  getIt.registerLazySingleton<AppRouter>(() => AppRouter());
  getIt.registerLazySingleton<AppPrefs>(() => AppPrefs(preferences));

  if (!kIsWeb) {
    getIt.registerLazySingleton<FlutterTts>(() => FlutterTts());
  }

  // Open + seed the course database before any course read. Seeding is a
  // one-shot on first launch (the DB is then cached); subsequent starts skip
  // the JSON assets entirely. Registered as a singleton so [SwahiliCourse]
  // can resolve it synchronously.
  final db = await _openAndSeedCourseDatabase();
  getIt.registerSingleton<CourseDatabase>(db);

  // Pre-load Swahili vocabulary so the synchronous [swahiliVocabById]
  // and [swahiliVocabByTranslation] lookups are populated before any
  // lesson is rendered. This is a one-shot cost at app start.
  await loadSwahiliVocabulary();

  // Pre-load grammar points so [swahiliGrammarPointById] is populated before
  // the grammar review screen renders.
  await loadSwahiliGrammarPoints();

  // Pre-load expressions so [swahiliExpressionsById] is populated before any
  // expression review cards are rendered.
  await loadSwahiliExpressions();
}

/// Opens the on-device course database and seeds it from the bundled JSON
/// assets if empty. Not supported on web (`NativeDatabase` needs native
/// `sqlite3`); a future revision can swap in a WASM database for web.
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
  await DatabaseSeeder(db).seedIfEmpty();
  return db;
}

Map<String, dynamic> _serializeUser(SerializableFirebaseUser user) =>
    user.toJson();

SerializableFirebaseUser _deserializeUser(dynamic value) =>
    SerializableFirebaseUser.fromJson(value as Map<String, dynamic>);
