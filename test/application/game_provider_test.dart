// Unit tests for GameProvider: XP accumulation, lesson completion tracking,
// reset, and streak-aware achievement gem unlocks. GameProvider routes gem
// bonuses through GetIt when registered, but falls back to a direct prefs
// write in unit tests, so we construct it standalone.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/domain/game/user_game_state.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late GameProvider game;

  setUp(() async {
    // setMockInitialValues does not clear an already-cached
    // StreamingSharedPreferences instance, so reset the game keys explicitly
    // between tests to avoid cross-test state leakage.
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.preferences.setInt(LocalStateKeys.score, 0);
    await prefs.preferences.setInt(LocalStateKeys.streak, 0);
    await prefs.preferences.setString(LocalStateKeys.lastStreakDate, '');
    await prefs.preferences
        .setStringList(LocalStateKeys.achievements, const []);
    game = GameProvider.forTesting(prefs);
  });

  int readScore() => prefs.preferences
      .getInt(LocalStateKeys.score, defaultValue: -1)
      .getValue();

  List<String> unlocked() =>
      prefs.preferences.getStringList(LocalStateKeys.achievements,
          defaultValue: <String>[]).getValue();

  group('awardXP / incrementScore', () {
    test('awardXP adds the event base to the score', () async {
      final gained = await game.awardXP(XPEvent.lessonComplete);
      expect(gained, XPEvent.lessonComplete.base);
      expect(readScore(), XPEvent.lessonComplete.base);
    });

    test('awardXP with multiplier scales the gain and rounds', () async {
      final gained =
          await game.awardXP(XPEvent.lessonComplete, multiplier: 1.5);
      expect(gained, 15); // 10 * 1.5
      expect(readScore(), 15);
    });

    test('awardXP accumulates across multiple calls', () async {
      await game.awardXP(XPEvent.lessonComplete);
      await game.awardXP(XPEvent.perfectLesson);
      expect(readScore(),
          XPEvent.lessonComplete.base + XPEvent.perfectLesson.base);
    });

    test('incrementScore(0) is a no-op', () async {
      await game.incrementScore(0);
      expect(readScore(), 0);
    });
  });

  group('lesson completion facade', () {
    // Behavior coverage (record/reset/stream semantics) lives in
    // lesson_progress_provider_test.dart; here we only pin that GameProvider
    // forwards to the wired LessonProgressProvider.
    test('recordLessonCompletion and resetLessonProgress reach the store',
        () async {
      await game.recordLessonCompletion(lessonId: 'l-1', wasPerfect: true);
      expect(game.isLessonCompleted('l-1'), isTrue);
      expect(game.isLessonPerfect('l-1'), isTrue);
      await game.resetLessonProgress();
      expect(game.completedLessonIds, isEmpty);
    });
  });

  group('resetAccountGameState', () {
    test('zeros score, streak, gems, lessons and emits consistent state',
        () async {
      await game.awardXP(XPEvent.lessonComplete);
      await game.recordLessonCompletion(lessonId: 'l-1', wasPerfect: true);
      await prefs.preferences.setInt(LocalStateKeys.streak, 5);
      await prefs.preferences.setInt(LocalStateKeys.gems, 40);
      await prefs.preferences.setStringList(
        LocalStateKeys.achievements,
        const ['xp_1000'],
      );

      final emitted = <UserGameState>[];
      final sub = game.getUserGameStateStream().listen(emitted.add);

      await game.resetAccountGameState();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      final state = game.currentUserGameState;
      expect(state.score, 0);
      expect(state.streak, 0);
      expect(state.gems, 0);
      expect(state.lessonsCompleted, 0);
      expect(state.perfectLessons, 0);
      expect(state.completedLessonIds, isEmpty);
      expect(state.achievements, isEmpty);
      expect(readScore(), 0);
      expect(
        prefs.preferences
            .getInt(LocalStateKeys.gems, defaultValue: -1)
            .getValue(),
        0,
      );

      // Final stream snapshot must also be fully zeroed (no partial race).
      expect(emitted, isNotEmpty);
      final last = emitted.last;
      expect(last.score, 0);
      expect(last.streak, 0);
      expect(last.gems, 0);
      expect(last.lessonsCompleted, 0);
    });
  });

  group('achievements separation', () {
    test(
        'incrementScore never writes the v1 achievement list (single-writer '
        'contract: unlocks belong to AchievementService)', () async {
      await game.incrementScore(1000);
      expect(unlocked(), isEmpty);
    });

    test('streak resolution still persists on score ticks', () async {
      await prefs.preferences.setInt(LocalStateKeys.streak, 2);
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      await prefs.preferences.setString(
        LocalStateKeys.lastStreakDate,
        DateTime(yesterday.year, yesterday.month, yesterday.day)
            .toIso8601String(),
      );
      await game.incrementScore(10);
      expect(
        prefs.preferences
            .getInt(LocalStateKeys.streak, defaultValue: 0)
            .getValue(),
        3,
      );
    });
  });
}
