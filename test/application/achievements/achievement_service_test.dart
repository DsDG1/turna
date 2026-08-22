// End-to-end tests for the unified AchievementService (成就系统焕新 P2/P3/P5):
// evaluate -> persist -> grant -> enqueue, two-phase crash recovery,
// concurrency, feedback queue, and account reset.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/achievement_test_stack.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences sp;
  late AppPrefs prefs;
  late AchievementTestStack stack;
  late AchievementService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sp = await StreamingSharedPreferences.instance;
    for (final key in sp.getKeys().getValue()) {
      await sp.remove(key);
    }
    prefs = AppPrefs(sp);
    stack = AchievementTestStack.build(prefs);
    service = stack.service;
    await service.ensureLoaded();
  });

  Future<void> completeLessons(int count, {int perfect = 0}) async {
    final progress = stack.lessonProgress;
    for (var i = 0; i < count; i++) {
      await progress.recordLessonCompletion(
        lessonId: 'lesson-$i',
        wasPerfect: i < perfect,
      );
    }
  }

  group('evaluateAndReward', () {
    test('first lesson unlocks tier 1 and pays its gems exactly once',
        () async {
      await completeLessons(1);

      final results = await service.evaluateAndReward();

      expect(results.map((r) => r.tierId), ['course_journey_001']);
      expect(stack.gemsProvider.balance, 8);
      final state = stack.stateRepository.current
          .tierState('course_journey_001')!;
      expect(state.rewardGranted, isTrue);
      expect(state.origin.name, 'live');
    });

    test('re-evaluation is idempotent and pays nothing again', () async {
      await completeLessons(1);
      await service.evaluateAndReward();
      final second = await service.evaluateAndReward();

      expect(second, isEmpty);
      expect(stack.gemsProvider.balance, 8);
    });

    test('a jump to 63 lessons unlocks all intermediate tiers in one pass',
        () async {
      await completeLessons(63);

      final results = await service.evaluateAndReward();

      expect(
        results.map((r) => r.tierId).toList(),
        ['course_journey_001', 'course_journey_002', 'course_journey_003',
            'course_journey_004'],
      );
      expect(stack.gemsProvider.balance, 8 + 12 + 18 + 25);
    });

    test('streak drop keeps unlocked tiers (no re-lock)', () async {
      await prefs.preferences.setInt(LocalStateKeys.streak, 7);
      await service.evaluateAndReward();
      expect(
        stack.stateRepository.current.isUnlocked('streak_journey_002'),
        isTrue,
      );

      // Streak breaks; nothing is removed and nothing new unlocks.
      await prefs.preferences.setInt(LocalStateKeys.streak, 0);
      final results = await service.evaluateAndReward();

      expect(results, isEmpty);
      expect(
        stack.stateRepository.current.isUnlocked('streak_journey_002'),
        isTrue,
      );
    });

    test('duplicate lesson ids never inflate the unique-lesson metric',
        () async {
      final progress = stack.lessonProgress;
      await progress.recordLessonCompletion(
        lessonId: 'same-lesson',
        wasPerfect: true,
      );
      await progress.recordLessonCompletion(
        lessonId: 'same-lesson',
        wasPerfect: true,
      );

      final results = await service.evaluateAndReward();

      expect(results.map((r) => r.tierId),
          ['course_journey_001', 'perfect_journey_001']);
    });

    test('XP milestones unlock from cumulative score', () async {
      await prefs.preferences.setInt(LocalStateKeys.score, 1000);
      final results = await service.evaluateAndReward();
      expect(
        results.map((r) => r.tierId),
        containsAll(['xp_journey_001', 'xp_journey_002', 'xp_journey_003']),
      );
    });

    test('review session delta drives the review journey', () async {
      await service.recordReviewSession(cardsAnswered: 12);

      expect(
        stack.stateRepository.current.isUnlocked('review_journey_001'),
        isTrue,
      );
      // The durable projection counter persisted the delta.
      expect(stack.projector.projection.totalReviewedCards, 12);
    });
  });

  group('crash recovery (two-phase rewards)', () {
    test('unlock persisted with rewardGranted=false is re-paid once on recovery',
        () async {
      await completeLessons(1);

      // Simulate a crash between persisting the unlock and granting gems:
      // evaluate but intercept the gem grant by running the phases manually.
      final results = await service.evaluateAndReward();
      expect(results, isNotEmpty);
      expect(stack.gemsProvider.balance, 8); // paid normally

      // Now simulate the crash state: mark the tier un-granted and re-run
      // recovery, exactly like a process that died between the two phases.
      final repo = stack.stateRepository;
      await repo.mutate(
        (current) => current.copyWith(
          unlockedTiers: {
            for (final e in current.unlockedTiers.entries)
              e.key: e.key == 'course_journey_001'
                  ? e.value.copyWith(
                      rewardGranted: false, rewardGrantedAt: null)
                  : e.value,
          },
        ),
      );

      await service.recoverPendingRewards();

      // Paid exactly once more — not doubled.
      expect(stack.gemsProvider.balance, 16);
      expect(
        repo.current.tierState('course_journey_001')!.rewardGranted,
        isTrue,
      );
      await service.recoverPendingRewards();
      expect(stack.gemsProvider.balance, 16, reason: 'recovery is idempotent');
    });
  });

  group('concurrency', () {
    test('parallel evaluations cannot double-unlock or double-pay', () async {
      await completeLessons(25);

      final results = await Future.wait([
        service.evaluateAndReward(),
        service.evaluateAndReward(),
        service.evaluateAndReward(),
      ]);

      final allTierIds =
          results.expand((r) => r).map((r) => r.tierId).toList();
      expect(allTierIds.toSet().length, allTierIds.length,
          reason: 'no tier unlocked twice');
      expect(allTierCount(allTierIds, 'course_journey_001'), 1);
      expect(stack.gemsProvider.balance, 8 + 12 + 18);
    });
  });

  group('feedback queue', () {
    test('unseen unlocks drain once and mark seen', () async {
      await completeLessons(10);
      await service.evaluateAndReward();

      expect(service.hasUnseenUnlocks, isTrue);
      final batch = await service.takeFeedbackBatch();
      expect(batch.length, 2); // tier 1 + tier 10
      expect(service.hasUnseenUnlocks, isFalse);

      final second = await service.takeFeedbackBatch();
      expect(second, isEmpty);
    });

    test('progress views expose unseen flag and persisted counts', () async {
      await completeLessons(10, perfect: 1);
      await service.evaluateAndReward();

      final views = service.progressViews();
      final course = views.firstWhere(
        (v) => v.seriesId == 'course_journey',
      );
      expect(course.completedTierCount, 2);
      expect(course.totalTierCount, 7);
      expect(course.nextTier?.target, 25);
      expect(course.isSeriesComplete, isFalse);
      expect(course.hasUnseenUnlock, isTrue);
    });
  });

  group('reset', () {
    test('resetAll clears state and projection', () async {
      await completeLessons(1);
      await service.evaluateAndReward();
      expect(stack.stateRepository.current.unlockedTiers, isNotEmpty);

      await service.resetAll();

      expect(stack.stateRepository.current.unlockedTiers, isEmpty);
      expect(stack.projector.projection.totalReviewedCards, 0);
      expect(stack.projector.projection.studiedWordIds, isEmpty);
    });
  });

  group('studied words projection', () {
    test('recordStudiedWords accumulates unique ids', () async {
      await service.recordStudiedWords(['w1', 'w2']);
      await service.recordStudiedWords(['w2', 'w3']);

      expect(stack.projector.projection.studiedWordIds, {'w1', 'w2', 'w3'});
    });
  });
}

int allTierCount(List<String> ids, String tierId) =>
    ids.where((id) => id == tierId).length;
