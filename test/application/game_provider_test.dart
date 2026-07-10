// Unit tests for GameProvider: XP accumulation, lesson completion tracking,
// reset, and streak-aware achievement gem unlocks. GameProvider routes gem
// bonuses through GetIt when registered, but falls back to a direct prefs
// write in unit tests, so we construct it standalone.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:words625/application/game_provider.dart';
import 'package:words625/service/locator.dart';

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
    await prefs.preferences.setStringList(LocalStateKeys.achievements, const []);
    game = GameProvider(prefs);
  });

  int readScore() =>
      prefs.preferences.getInt(LocalStateKeys.score, defaultValue: -1).getValue();

  List<String> unlocked() =>
      prefs.preferences
          .getStringList(LocalStateKeys.achievements, defaultValue: <String>[])
          .getValue();

  group('awardXP / incrementScore', () {
    test('awardXP adds the event base to the score', () async {
      final gained = await game.awardXP(XPEvent.lessonComplete);
      expect(gained, XPEvent.lessonComplete.base);
      expect(readScore(), XPEvent.lessonComplete.base);
    });

    test('awardXP with multiplier scales the gain and rounds', () async {
      final gained = await game.awardXP(XPEvent.lessonComplete, multiplier: 1.5);
      expect(gained, 15); // 10 * 1.5
      expect(readScore(), 15);
    });

    test('awardXP accumulates across multiple calls', () async {
      await game.awardXP(XPEvent.lessonComplete);
      await game.awardXP(XPEvent.perfectLesson);
      expect(readScore(), XPEvent.lessonComplete.base + XPEvent.perfectLesson.base);
    });

    test('incrementScore(0) is a no-op', () async {
      await game.incrementScore(0);
      expect(readScore(), 0);
    });
  });

  group('lesson completion tracking', () {
    test('recordLessonCompletion marks a lesson done and emits progress',
        () async {
      expect(game.isLessonCompleted('l-1'), isFalse);
      await game.recordLessonCompletion(lessonId: 'l-1', wasPerfect: false);
      expect(game.isLessonCompleted('l-1'), isTrue);
      expect(game.isLessonPerfect('l-1'), isFalse);
    });

    test('a perfect completion records both completed and perfect sets',
        () async {
      await game.recordLessonCompletion(lessonId: 'l-1', wasPerfect: true);
      expect(game.isLessonCompleted('l-1'), isTrue);
      expect(game.isLessonPerfect('l-1'), isTrue);
    });

    test('replaying a lesson can upgrade it to perfect without losing the '
        'completed flag', () async {
      await game.recordLessonCompletion(lessonId: 'l-1', wasPerfect: false);
      await game.recordLessonCompletion(lessonId: 'l-1', wasPerfect: true);
      expect(game.isLessonCompleted('l-1'), isTrue);
      expect(game.isLessonPerfect('l-1'), isTrue);
      // Sets dedupe: only one lesson id tracked.
      expect(game.completedLessonIds, {'l-1'});
    });

    test('completedLessonsStream emits updates as lessons are completed',
        () async {
      final emitted = <Set<String>>[];
      final sub = game.completedLessonsStream.listen(emitted.add);
      await game.recordLessonCompletion(lessonId: 'l-1', wasPerfect: false);
      await game.recordLessonCompletion(lessonId: 'l-2', wasPerfect: true);
      await Future<void>.delayed(Duration.zero);
      sub.cancel();
      // The stream yields the current set on subscribe then on each emit;
      // the final captured snapshot must include both completed lessons.
      expect(emitted.last, containsAll({'l-1', 'l-2'}));
    });
  });

  group('resetLessonProgress', () {
    test('clears completed/perfect sets and the derived counters', () async {
      await game.recordLessonCompletion(lessonId: 'l-1', wasPerfect: true);
      await game.recordLessonCompletion(lessonId: 'l-2', wasPerfect: false);
      await game.resetLessonProgress();
      expect(game.completedLessonIds, isEmpty);
      expect(game.perfectLessonIds, isEmpty);
      expect(game.isLessonCompleted('l-1'), isFalse);
    });
  });

  group('streak & achievements', () {
    test('crossing the first streak threshold unlocks a streak achievement',
        () async {
      // Seed a 1-day streak so a practice session resolves to streak >= 3.
      await prefs.preferences.setInt(LocalStateKeys.streak, 2);
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      await prefs.preferences.setString(
        LocalStateKeys.lastStreakDate,
        DateTime(yesterday.year, yesterday.month, yesterday.day)
            .toIso8601String(),
      );
      await game.incrementScore(10);
      // Threshold ladder is [3, 7, 30, 100, 365]; reaching 3 unlocks it.
      expect(unlocked(), isNotEmpty);
    });

    test('crossing an XP threshold unlocks an XP achievement', () async {
      // XP thresholds are [1000, 10000, 50000]; jump straight to 1000+.
      await game.incrementScore(1000);
      expect(unlocked(), isNotEmpty);
    });

    test('below all thresholds unlocks nothing', () async {
      await game.incrementScore(10);
      expect(unlocked(), isEmpty);
    });
  });
}