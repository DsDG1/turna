// Dart imports:
import 'dart:core';

// Project imports:
import 'package:turna/domain/achievements/achievement_definition.dart';
import 'package:turna/domain/achievements/achievement_state.dart';
import 'package:turna/domain/achievements/achievement_unlock_result.dart';

/// A consistent point-in-time view of every achievement metric. Built by
/// `AchievementMetricProjector` — the evaluator never reads prefs itself.
class AchievementMetricSnapshot {
  final int uniqueLessonsCompleted;
  final int uniquePerfectLessons;
  final int currentStreakDays;
  final int totalXp;
  final int maxDailyXp;
  final int totalReviewedCards;
  final int uniqueWordsStudied;
  final DateTime calculatedAt;

  AchievementMetricSnapshot({
    this.uniqueLessonsCompleted = 0,
    this.uniquePerfectLessons = 0,
    this.currentStreakDays = 0,
    this.totalXp = 0,
    this.maxDailyXp = 0,
    this.totalReviewedCards = 0,
    this.uniqueWordsStudied = 0,
    DateTime? calculatedAt,
  }) : calculatedAt = calculatedAt ?? _epoch;

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  int metricValue(AchievementMetric metric) {
    switch (metric) {
      case AchievementMetric.uniqueLessonsCompleted:
        return uniqueLessonsCompleted;
      case AchievementMetric.uniquePerfectLessons:
        return uniquePerfectLessons;
      case AchievementMetric.currentStreakDays:
        return currentStreakDays;
      case AchievementMetric.totalXp:
        return totalXp;
      case AchievementMetric.maxDailyXp:
        return maxDailyXp;
      case AchievementMetric.totalReviewedCards:
        return totalReviewedCards;
      case AchievementMetric.uniqueWordsStudied:
        return uniqueWordsStudied;
    }
  }
}

/// Thrown by [AchievementCatalogContract.validate] when the catalog violates
/// an invariant. Fail-fast at test time so a bad edit can never ship.
class AchievementCatalogViolation implements Exception {
  final String message;
  const AchievementCatalogViolation(this.message);

  @override
  String toString() => 'AchievementCatalogViolation: $message';
}

/// Structural invariants every catalog revision must satisfy.
class AchievementCatalogContract {
  const AchievementCatalogContract._();

  static void validate(Iterable<AchievementSeriesDefinition> series) {
    final seriesIds = <String>{};
    final tierIds = <String>{};
    for (final s in series) {
      if (!seriesIds.add(s.id)) {
        throw AchievementCatalogViolation('duplicate series id ${s.id}');
      }
      if (s.tiers.isEmpty) {
        throw AchievementCatalogViolation('series ${s.id} has no tiers');
      }
      var previousTarget = -1;
      for (final tier in s.tiers) {
        if (!tierIds.add(tier.id)) {
          throw AchievementCatalogViolation('duplicate tier id ${tier.id}');
        }
        if (tier.target <= previousTarget) {
          throw AchievementCatalogViolation(
            'series ${s.id} tier ${tier.id} target ${tier.target} is not '
            'strictly increasing',
          );
        }
        if (tier.target <= 0) {
          throw AchievementCatalogViolation(
            'series ${s.id} tier ${tier.id} target must be positive',
          );
        }
        if (tier.gemReward < 0) {
          throw AchievementCatalogViolation(
            'series ${s.id} tier ${tier.id} has negative gem reward',
          );
        }
        previousTarget = tier.target;
      }
    }
  }
}

/// Pure evaluation: given definitions, prior state, and a metric snapshot,
/// return the tiers that should be newly unlocked. Re-running with the same
/// inputs yields nothing; metric drops never remove existing unlocks.
class AchievementEvaluator {
  const AchievementEvaluator._();

  /// Evaluate one series against the snapshot.
  static List<AchievementUnlockResult> evaluateSeries({
    required AchievementSeriesDefinition series,
    required AchievementStateDocument state,
    required AchievementMetricSnapshot snapshot,
    required AchievementUnlockOrigin origin,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final value = snapshot.metricValue(series.metric);
    final results = <AchievementUnlockResult>[];
    for (final tier in series.tiers) {
      if (value < tier.target) break;
      if (state.isUnlocked(tier.id)) continue;
      results.add(AchievementUnlockResult(
        seriesId: series.id,
        tierId: tier.id,
        target: tier.target,
        gemReward: tier.gemReward,
        cosmeticRewardId: tier.cosmeticRewardId,
        unlockedAt: timestamp,
        origin: origin,
      ));
    }
    return results;
  }

  /// Evaluate every series in [seriesList]; order follows catalog order.
  static List<AchievementUnlockResult> evaluate({
    required Iterable<AchievementSeriesDefinition> seriesList,
    required AchievementStateDocument state,
    required AchievementMetricSnapshot snapshot,
    required AchievementUnlockOrigin origin,
    DateTime? now,
  }) {
    final results = <AchievementUnlockResult>[];
    for (final series in seriesList) {
      results.addAll(evaluateSeries(
        series: series,
        state: state,
        snapshot: snapshot,
        origin: origin,
        now: now,
      ));
    }
    return results;
  }
}
