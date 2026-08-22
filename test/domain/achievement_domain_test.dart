// Achievement catalog contract tests + pure-evaluator boundary tests
// (成就系统焕新 P0/P1). These encode the hard product constraints:
// 课程行者终点 500 唯一完成课时、完美主义者终点 100 唯一完美课时。

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/achievements/achievement_evaluator.dart';
import 'package:turna/domain/achievements/achievement_catalog.dart';
import 'package:turna/domain/achievements/achievement_definition.dart';
import 'package:turna/domain/achievements/achievement_state.dart';

void main() {
  group('catalog contract', () {
    test('passes structural validation', () {
      expect(() => AchievementCatalogContract.validate(AchievementCatalog.allSeries),
          returnsNormally);
    });

    test('course journey final target is exactly 500 (hard constraint)', () {
      final series = AchievementCatalog.seriesById(
        AchievementCatalog.courseJourneyId,
      )!;
      expect(series.tiers.last.target, 500);
      expect(series.metric, AchievementMetric.uniqueLessonsCompleted);
    });

    test('perfect journey final target is exactly 100 (hard constraint)', () {
      final series = AchievementCatalog.seriesById(
        AchievementCatalog.perfectJourneyId,
      )!;
      expect(series.tiers.last.target, 100);
      expect(series.metric, AchievementMetric.uniquePerfectLessons);
    });

    test('recommended ladders match the plan', () {
      List<int> ladder(String id) => AchievementCatalog.seriesById(id)!
          .tiers
          .map((t) => t.target)
          .toList();

      expect(ladder(AchievementCatalog.courseJourneyId),
          [1, 10, 25, 50, 100, 250, 500]);
      expect(ladder(AchievementCatalog.perfectJourneyId),
          [1, 5, 10, 20, 50, 100]);
      expect(ladder(AchievementCatalog.streakJourneyId),
          [3, 7, 14, 30, 75, 125, 200, 365]);
      expect(ladder(AchievementCatalog.xpJourneyId),
          [100, 500, 1000, 5000, 10000, 50000]);
      expect(ladder(AchievementCatalog.dailyFocusId),
          [50, 100, 250, 500, 1000, 2000]);
      expect(ladder(AchievementCatalog.reviewJourneyId),
          [10, 50, 200, 500, 1000, 5000]);
      expect(ladder(AchievementCatalog.vocabularyJourneyId),
          [10, 25, 50, 100, 250, 500, 1000]);
    });

    test('every tier gem reward equals its rarity default', () {
      for (final series in AchievementCatalog.allSeries) {
        for (final tier in series.tiers) {
          expect(tier.gemReward, tier.rarity.defaultGemReward,
              reason: '${tier.id} should match ${tier.rarity.name} default');
        }
      }
    });

    test('gem rewards never exceed the diamond default (no gem inflation)', () {
      for (final series in AchievementCatalog.allSeries) {
        for (final tier in series.tiers) {
          expect(tier.gemReward,
              lessThanOrEqualTo(AchievementRarity.diamond.defaultGemReward));
        }
      }
    });

    test('vocabulary journey is deferred (unpublished)', () {
      final series = AchievementCatalog.seriesById(
        AchievementCatalog.vocabularyJourneyId,
      )!;
      expect(series.published, isFalse);
      expect(AchievementCatalog.publishedSeries, isNot(contains(series)));
    });

    test('final tiers of the two flagship series carry cosmetic rewards', () {
      final course = AchievementCatalog.seriesById(
        AchievementCatalog.courseJourneyId,
      )!;
      final perfect = AchievementCatalog.seriesById(
        AchievementCatalog.perfectJourneyId,
      )!;
      expect(course.tiers.last.cosmeticRewardId,
          AchievementCatalog.cosmeticTitleFarWalker);
      expect(perfect.tiers.last.cosmeticRewardId,
          AchievementCatalog.cosmeticTitleHundredFlawless);
    });

    test('contract validation rejects duplicate ids', () {
      final series = AchievementSeriesDefinition(
        id: 'dupe',
        metric: AchievementMetric.totalXp,
        titleKey: 'dupe',
        descriptionKey: 'dupe',
        iconKey: 'dupe',
        tiers: [
          const AchievementTierDefinition(
            id: 'dupe_1',
            ordinal: 1,
            target: 10,
            gemReward: 5,
            rarity: AchievementRarity.bronze,
          ),
          const AchievementTierDefinition(
            id: 'dupe_1',
            ordinal: 2,
            target: 20,
            gemReward: 8,
            rarity: AchievementRarity.silver,
          ),
        ],
      );
      expect(
        () => AchievementCatalogContract.validate([series]),
        throwsA(isA<AchievementCatalogViolation>()),
      );
    });

    test('contract validation rejects non-increasing targets', () {
      final series = AchievementSeriesDefinition(
        id: 'flat',
        metric: AchievementMetric.totalXp,
        titleKey: 'flat',
        descriptionKey: 'flat',
        iconKey: 'flat',
        tiers: [
          const AchievementTierDefinition(
            id: 'flat_1',
            ordinal: 1,
            target: 10,
            gemReward: 5,
            rarity: AchievementRarity.bronze,
          ),
          const AchievementTierDefinition(
            id: 'flat_2',
            ordinal: 2,
            target: 10,
            gemReward: 8,
            rarity: AchievementRarity.silver,
          ),
        ],
      );
      expect(
        () => AchievementCatalogContract.validate([series]),
        throwsA(isA<AchievementCatalogViolation>()),
      );
    });

    test('contract validation rejects empty series', () {
      final series = AchievementSeriesDefinition(
        id: 'empty',
        metric: AchievementMetric.totalXp,
        titleKey: 'empty',
        descriptionKey: 'empty',
        iconKey: 'empty',
        tiers: const [],
      );
      expect(
        () => AchievementCatalogContract.validate([series]),
        throwsA(isA<AchievementCatalogViolation>()),
      );
    });
  });

  group('completedTierCount', () {
    final course = AchievementCatalog.seriesById(
      AchievementCatalog.courseJourneyId,
    )!;

    test('is 0 at zero progress (single-target series cannot pre-complete)', () {
      expect(course.completedTierCount(0), 0);
    });

    test('counts reached tiers only', () {
      expect(course.completedTierCount(1), 1);
      expect(course.completedTierCount(9), 1);
      expect(course.completedTierCount(63), 4); // 1, 10, 25, 50
    });

    test('course journey does not complete at 499', () {
      expect(course.completedTierCount(499), course.tiers.length - 1);
      expect(course.completedTierCount(499), isNot(course.tiers.length));
    });

    test('course journey completes exactly at 500', () {
      expect(course.completedTierCount(500), course.tiers.length);
      expect(course.completedTierCount(9999), course.tiers.length);
    });

    test('nextTierAfter mirrors completedTierCount', () {
      expect(course.nextTierAfter(0)?.target, 1);
      expect(course.nextTierAfter(1)?.target, 10);
      expect(course.nextTierAfter(499)?.target, 500);
      expect(course.nextTierAfter(500), isNull);
    });

    test('perfect journey does not complete at 99 / completes at 100', () {
      final perfect = AchievementCatalog.seriesById(
        AchievementCatalog.perfectJourneyId,
      )!;
      expect(perfect.completedTierCount(99), perfect.tiers.length - 1);
      expect(perfect.completedTierCount(100), perfect.tiers.length);
    });
  });

  group('AchievementEvaluator', () {
    final course = AchievementCatalog.seriesById(
      AchievementCatalog.courseJourneyId,
    )!;
    final state = AchievementStateDocument.empty;

    AchievementMetricSnapshot snapshot(int lessons) =>
        AchievementMetricSnapshot(uniqueLessonsCompleted: lessons);

    test('no unlocks at zero progress', () {
      final results = AchievementEvaluator.evaluateSeries(
        series: course,
        state: state,
        snapshot: snapshot(0),
        origin: AchievementUnlockOrigin.live,
      );
      expect(results, isEmpty);
    });

    test('does not unlock below a target', () {
      expect(
        AchievementEvaluator.evaluateSeries(
          series: course,
          state: state,
          snapshot: snapshot(499),
          origin: AchievementUnlockOrigin.live,
        ).map((r) => r.tierId),
        isNot(contains('course_journey_007')),
      );
    });

    test('unlocks exactly at a target', () {
      final results = AchievementEvaluator.evaluateSeries(
        series: course,
        state: state,
        snapshot: snapshot(500),
        origin: AchievementUnlockOrigin.live,
      );
      expect(results.length, course.tiers.length);
      expect(results.last.tierId, 'course_journey_007');
      expect(results.last.cosmeticRewardId, isNotNull);
    });

    test('a jump from 0 to 63 returns every intermediate tier', () {
      final results = AchievementEvaluator.evaluateSeries(
        series: course,
        state: state,
        snapshot: snapshot(63),
        origin: AchievementUnlockOrigin.live,
      );
      expect(results.map((r) => r.target).toList(), [1, 10, 25, 50]);
    });

    test('re-evaluating the same snapshot unlocks nothing (idempotent)', () {
      final first = AchievementEvaluator.evaluateSeries(
        series: course,
        state: state,
        snapshot: snapshot(25),
        origin: AchievementUnlockOrigin.live,
      );
      final doc = AchievementStateDocument(
        unlockedTiers: {
          for (final r in first)
            r.tierId: AchievementTierState(
              tierId: r.tierId,
              unlockedAt: r.unlockedAt,
            ),
        },
      );
      final second = AchievementEvaluator.evaluateSeries(
        series: course,
        state: doc,
        snapshot: snapshot(25),
        origin: AchievementUnlockOrigin.live,
      );
      expect(second, isEmpty);
    });

    test('metric drops never re-lock persisted unlocks', () {
      final streak = AchievementCatalog.seriesById(
        AchievementCatalog.streakJourneyId,
      )!;
      final doc = AchievementStateDocument(
        unlockedTiers: {
          'streak_journey_001': AchievementTierState(
            tierId: 'streak_journey_001',
            unlockedAt: DateTime.now(),
          ),
        },
      );
      final results = AchievementEvaluator.evaluateSeries(
        series: streak,
        state: doc,
        snapshot: AchievementMetricSnapshot(),
        origin: AchievementUnlockOrigin.live,
      );
      expect(results, isEmpty);
      expect(doc.isUnlocked('streak_journey_001'), isTrue);
    });
  });
}
