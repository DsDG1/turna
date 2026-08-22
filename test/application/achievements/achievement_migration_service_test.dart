// v1 -> v2 achievement migration tests (成就系统焕新 P3): id mapping,
// authoritative backfill, unknown-id diagnostics, idempotency, and the
// 500/100 boundary migration rules.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/achievement_test_stack.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences sp;
  late AppPrefs prefs;
  late AchievementTestStack stack;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sp = await StreamingSharedPreferences.instance;
    for (final key in sp.getKeys().getValue()) {
      await sp.remove(key);
    }
    prefs = AppPrefs(sp);
    stack = AchievementTestStack.build(prefs);
  });

  Future<void> seedLessonProgress({
    int completed = 0,
    int perfect = 0,
    int legacyCompleted = -1,
    int legacyPerfect = -1,
  }) async {
    final progress = stack.lessonProgress;
    for (var i = 0; i < completed; i++) {
      await progress.recordLessonCompletion(
        lessonId: 'lesson-$i',
        wasPerfect: i < perfect,
      );
    }
    if (legacyCompleted >= 0) {
      await prefs.preferences.setInt(
        LocalStateKeys.lessonsCompleted,
        legacyCompleted,
      );
    }
    if (legacyPerfect >= 0) {
      await prefs.preferences.setInt(
        LocalStateKeys.perfectLessons,
        legacyPerfect,
      );
    }
  }

  group('empty / fresh accounts', () {
    test('empty account: migration runs, backfills nothing', () async {
      final report = await stack.migrationService.runIfNeeded();
      expect(report.ran, isTrue);
      expect(report.backfilledTiers, 0);
      expect(stack.stateRepository.current.unlockedTiers, isEmpty);
    });

    test('second run is a no-op guarded by the version marker', () async {
      await stack.migrationService.runIfNeeded();
      final again = await stack.migrationService.runIfNeeded();
      expect(again.ran, isFalse);
    });
  });

  group('authoritative backfill', () {
    test('63 completed lessons backfill tiers 1/10/25/50 without gems',
        () async {
      await seedLessonProgress(completed: 63, perfect: 5);
      final gemsBefore = stack.gemsProvider.balance;

      final report = await stack.migrationService.runIfNeeded();

      expect(report.backfilledTiers, 6); // course 1,10,25,50 + perfect 1,5
      final doc = stack.stateRepository.current;
      expect(doc.isUnlocked('course_journey_004'), isTrue);
      expect(doc.isUnlocked('course_journey_005'), isFalse);
      expect(doc.isUnlocked('perfect_journey_002'), isTrue);
      // Migration never pays gems (plan §6.3).
      expect(stack.gemsProvider.balance, gemsBefore);
      for (final state in doc.unlockedTiers.values) {
        expect(state.origin.name, 'migration');
        expect(state.rewardGranted, isTrue);
        expect(state.seen, isTrue, reason: 'backfill is born seen');
      }
    });

    test('499 completed lessons do NOT unlock the 500 final tier', () async {
      await seedLessonProgress(completed: 499);
      await stack.migrationService.runIfNeeded();
      final doc = stack.stateRepository.current;
      expect(doc.isUnlocked('course_journey_006'), isTrue); // 250
      expect(doc.isUnlocked('course_journey_007'), isFalse); // 500
    });

    test('500 completed lessons unlock the 500 final tier', () async {
      await seedLessonProgress(completed: 500);
      await stack.migrationService.runIfNeeded();
      expect(
        stack.stateRepository.current.isUnlocked('course_journey_007'),
        isTrue,
      );
    });

    test('legacy integer counter above the id set does not inflate unlocks',
        () async {
      // Legacy counter says 60 but only 3 real lesson ids exist.
      await seedLessonProgress(completed: 3, legacyCompleted: 60);
      final report = await stack.migrationService.runIfNeeded();
      final doc = stack.stateRepository.current;
      expect(doc.isUnlocked('course_journey_002'), isFalse); // 10 not reached
      expect(report.countConflicts, isNotEmpty);
    });
  });

  group('v1 id mapping', () {
    test('xp_* ids unlock exact xp tiers even if score dropped', () async {
      await prefs.preferences.setStringList(
        LocalStateKeys.achievements,
        ['xp_1000', 'xp_10000'],
      );
      // Current total XP is only 50 — the v1 grants must survive.
      await prefs.preferences.setInt(LocalStateKeys.score, 50);

      await stack.migrationService.runIfNeeded();

      final doc = stack.stateRepository.current;
      expect(doc.isUnlocked('xp_journey_003'), isTrue); // 1000
      expect(doc.isUnlocked('xp_journey_005'), isTrue); // 10000
      expect(doc.isUnlocked('xp_journey_006'), isFalse); // 50000
      expect(doc.isUnlocked('xp_journey_001'), isFalse); // 100 not reached
    });

    test('streak_* ids unlock exact streak tiers', () async {
      await prefs.preferences.setStringList(
        LocalStateKeys.achievements,
        ['streak_3', 'streak_7', 'streak_30', 'streak_365'],
      );
      await stack.migrationService.runIfNeeded();

      final doc = stack.stateRepository.current;
      expect(doc.isUnlocked('streak_journey_001'), isTrue);
      expect(doc.isUnlocked('streak_journey_002'), isTrue);
      expect(doc.isUnlocked('streak_journey_004'), isTrue);
      expect(doc.isUnlocked('streak_journey_008'), isTrue);
      // Untouched middle tiers are not implied by streak_365 (exact mapping).
      expect(doc.isUnlocked('streak_journey_003'), isFalse);
    });

    test('streak_100 never maps onto the 125-day tier', () async {
      await prefs.preferences.setStringList(
        LocalStateKeys.achievements,
        ['streak_100'],
      );
      final report = await stack.migrationService.runIfNeeded();

      expect(report.hadLegacyStreak100, isTrue);
      expect(
        stack.stateRepository.current.isUnlocked('streak_journey_006'),
        isFalse,
        reason: 'legacy 100-day commemorative state must not unlock 125',
      );
      expect(
        stack.stateRepository.current.migrationDiagnostics,
        contains('legacy:streak_100'),
      );
    });

    test('champion / sharpshooter / sage / scholar / winner / wildfire are '
        'recomputed from metrics, not trusted as full completion', () async {
      await seedLessonProgress(completed: 2, perfect: 1);
      await prefs.preferences.setStringList(
        LocalStateKeys.achievements,
        ['champion', 'sharpshooter', 'sage', 'scholar', 'winner', 'wildfire'],
      );

      await stack.migrationService.runIfNeeded();

      final doc = stack.stateRepository.current;
      // Recomputed: 2 lessons -> tier 1 only; 1 perfect -> tier 1 only.
      expect(doc.isUnlocked('course_journey_001'), isTrue);
      expect(doc.isUnlocked('course_journey_002'), isFalse);
      expect(doc.isUnlocked('perfect_journey_001'), isTrue);
      expect(doc.isUnlocked('perfect_journey_002'), isFalse);
    });

    test('unknown ids land in diagnostics without failing the migration',
        () async {
      await prefs.preferences.setStringList(
        LocalStateKeys.achievements,
        ['xp_1000', 'mystery_badge', 'another_unknown'],
      );

      final report = await stack.migrationService.runIfNeeded();

      expect(report.unknownIds, ['mystery_badge', 'another_unknown']);
      expect(
        stack.stateRepository.current.migrationDiagnostics,
        containsAll(['unknown:mystery_badge', 'unknown:another_unknown']),
      );
    });
  });

  group('idempotency', () {
    test('forced re-run changes nothing (set semantics)', () async {
      await seedLessonProgress(completed: 25, perfect: 10);
      await stack.migrationService.runIfNeeded();
      final doc1 = stack.stateRepository.current;

      // Simulate the version marker being lost: run the migration body again.
      await prefs.preferences.remove(LocalStateKeys.achievementsMigrationVersion);
      await stack.migrationService.runIfNeeded();
      final doc2 = stack.stateRepository.current;

      expect(doc2.unlockedTiers.keys, equals(doc1.unlockedTiers.keys));
      expect(stack.gemsProvider.balance, 0);
    });
  });
}
