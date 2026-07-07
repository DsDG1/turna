// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:flutter_tts/flutter_tts.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:words625/core/logger.dart';
import 'package:words625/di/injection.dart';
import 'package:words625/domain/auth/local_user.dart';
import 'package:words625/routing/routing.dart';

class AppPrefs {
  final StreamingSharedPreferences preferences;

  AppPrefs(
    this.preferences,
  )   : currentLanguage = preferences.getString(
          PrefsConstants.currentLanguage,
          defaultValue: "kannada",
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
  static const String leagueXp = 'game.leagueXp';
  static const String dailyXpGoal = 'game.dailyXpGoal';
  static const String dailyXpEarned = 'game.dailyXpEarned';
  static const String lastDailyReset = 'game.lastDailyReset';
  static const String lessonsCompleted = 'game.lessonsCompleted';
  static const String perfectLessons = 'game.perfectLessons';
  static const String streakFreezes = 'game.streakFreezes';
  static const String streakFreezeActive = 'game.streakFreezeActive';
  static const String streakWasBroken = 'game.streakWasBroken';
  static const String streakRepairRequired = 'game.streakRepairRequired';
  static const String streakRepairProgress = 'game.streakRepairProgress';
  static const String streakRepairTarget = 'game.streakRepairTarget';
  static const String streakBeforeBreak = 'game.streakBeforeBreak';
  static const String wordsLearned = 'game.wordsLearned';
  static const String friendsCount = 'game.friendsCount';

  // Currency
  static const String gems = 'currency.gems';
  static const String hearts = 'currency.hearts';
  static const String heartsRefillAt = 'currency.heartsRefillAt';
  static const String followRewardClaimed = 'currency.followRewardClaimed';
  static const String validatedShareCount = 'currency.validatedShareCount';
  static const String claimedShareCount = 'currency.claimedShareCount';

  // Achievements
  static const String achievements = 'achievements.unlocked';

  // SRS — JSON-serialized Map<String, SrsWord> keyed by wordId.
  static const String srsState = 'srs.state';
}

/// Making AppPrefs injectable
Future<void> setupLocator() async {
  final preferences = await StreamingSharedPreferences.instance;
  getIt.registerLazySingleton<AppRouter>(() => AppRouter());
  getIt.registerLazySingleton<AppPrefs>(() => AppPrefs(preferences));

  if (!kIsWeb) {
    getIt.registerLazySingleton<FlutterTts>(
        () => FlutterTts()..setLanguage("en-US"));
  }
}

Map<String, dynamic> _serializeUser(SerializableFirebaseUser user) =>
    user.toJson();

SerializableFirebaseUser _deserializeUser(dynamic value) =>
    SerializableFirebaseUser.fromJson(value as Map<String, dynamic>);