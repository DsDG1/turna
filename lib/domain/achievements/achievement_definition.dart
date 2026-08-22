/// Metrics that drive achievement evaluation. Each metric has exactly one
/// authoritative source (see `AchievementMetricProjector`); the evaluator
/// never recomputes them from raw prefs.
enum AchievementMetric {
  /// Unique completed lesson ids (`LessonProgressProvider.completedLessonIds`).
  uniqueLessonsCompleted,

  /// Unique perfect lesson ids (`LessonProgressProvider.perfectLessonIds`).
  uniquePerfectLessons,

  /// Current streak in days (`StreakProvider`). Unlocks persist even when the
  /// streak later drops — only progress display follows the live value.
  currentStreakDays,

  /// Cumulative XP (`ScoreProvider`).
  totalXp,

  /// Highest XP earned in a single local day (study-log daily aggregates +
  /// persistent projection).
  maxDailyXp,

  /// Cumulative count of formally submitted review card answers across
  /// Turna SRS, grammar review, and Anki review.
  totalReviewedCards,

  /// Unique word/expression ids seen in completed lessons or formally
  /// submitted reviews (persistent projection).
  uniqueWordsStudied,
}

/// Badge material ladder. Display names and default gem rewards live here so
/// the catalog never hardcodes gem values by array index.
enum AchievementRarity {
  sprout(displayName: '萌芽', defaultGemReward: 5),
  bronze(displayName: '青铜', defaultGemReward: 8),
  silver(displayName: '白银', defaultGemReward: 12),
  gold(displayName: '黄金', defaultGemReward: 18),
  emerald(displayName: '翡翠', defaultGemReward: 25),
  ruby(displayName: '红宝石', defaultGemReward: 35),
  amethyst(displayName: '紫晶', defaultGemReward: 45),
  diamond(displayName: '钻石', defaultGemReward: 60);

  final String displayName;
  final int defaultGemReward;

  const AchievementRarity({required this.displayName, required this.defaultGemReward});
}

/// One unlockable badge inside a series. Tier ids are stable forever: the
/// pair (series, target) must keep its meaning, otherwise a new tier id is
/// created instead of mutating an existing one.
class AchievementTierDefinition {
  final String id;
  final int ordinal;

  /// Metric value required to unlock this tier.
  final int target;

  /// Gems granted on live unlock. Migration backfills never pay this.
  final int gemReward;

  /// Optional commemorative reward (title / avatar ring / card style). May be
  /// set on final tiers instead of large gem payouts.
  final String? cosmeticRewardId;

  final AchievementRarity rarity;

  const AchievementTierDefinition({
    required this.id,
    required this.ordinal,
    required this.target,
    required this.gemReward,
    required this.rarity,
    this.cosmeticRewardId,
  });
}

/// A badge series (e.g. 课程行者). Pure data — icons, colors, and localized
/// strings are resolved by the UI catalog from [iconKey] / [titleKey].
class AchievementSeriesDefinition {
  final String id;
  final AchievementMetric metric;
  final String titleKey;
  final String descriptionKey;
  final String iconKey;

  /// Ordered by strictly increasing [AchievementTierDefinition.target].
  final List<AchievementTierDefinition> tiers;

  /// Unpublished series exist in code (projector coverage, migration) but are
  /// hidden from UI and never evaluated for live unlocks.
  final bool published;

  const AchievementSeriesDefinition({
    required this.id,
    required this.metric,
    required this.titleKey,
    required this.descriptionKey,
    required this.iconKey,
    required this.tiers,
    this.published = true,
  });

  AchievementTierDefinition? tierById(String id) {
    for (final tier in tiers) {
      if (tier.id == id) return tier;
    }
    return null;
  }

  /// First tier whose target is strictly greater than [metricValue]; null
  /// when every tier is reached.
  AchievementTierDefinition? nextTierAfter(int metricValue) {
    for (final tier in tiers) {
      if (metricValue < tier.target) return tier;
    }
    return null;
  }

  /// Number of tiers whose target has been reached. 0-based: a fresh account
  /// has completed 0 tiers even for single-target series.
  int completedTierCount(int metricValue) {
    var count = 0;
    for (final tier in tiers) {
      if (metricValue >= tier.target) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  bool get isFinalTierCommemorative =>
      tiers.isNotEmpty && tiers.last.cosmeticRewardId != null;
}
