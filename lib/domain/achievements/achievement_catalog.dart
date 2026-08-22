import 'package:turna/domain/achievements/achievement_definition.dart';

/// Single source of truth for achievement definitions (plan: 成就系统焕新
/// §3). Hard constraints encoded here and guarded by catalog contract tests:
///
/// - 课程行者最终层级 = 500 唯一完成课时（不可下调）。
/// - 完美主义者最终层级 = 100 唯一完美课时（不可下调）。
///
/// Tier ids are `{seriesId}_{ordinal}` and must never change meaning. If a
/// target's semantics change, add a new tier id instead of editing one.
class AchievementCatalog {
  const AchievementCatalog._();

  static const String courseJourneyId = 'course_journey';
  static const String perfectJourneyId = 'perfect_journey';
  static const String streakJourneyId = 'streak_journey';
  static const String xpJourneyId = 'xp_journey';
  static const String dailyFocusId = 'daily_focus';
  static const String reviewJourneyId = 'review_journey';
  static const String vocabularyJourneyId = 'vocabulary_journey';

  /// Commemorative final-tier rewards (titles / decorations). Gem payouts for
  /// final tiers stay at the rarity default — no 500–1000 gem injections.
  static const String cosmeticTitleFarWalker = 'title_far_walker';
  static const String cosmeticTitleHundredFlawless = 'title_hundred_flawless';
  static const String cosmeticStreak365 = 'cosmetic_streak_365';

  /// All series, in fixed catalog display order.
  static const List<AchievementSeriesDefinition> allSeries = [
    _courseJourney,
    _perfectJourney,
    _streakJourney,
    _xpJourney,
    _dailyFocus,
    _reviewJourney,
    _vocabularyJourney,
  ];

  /// Series evaluated for real unlocks and shown in UI.
  static List<AchievementSeriesDefinition> get publishedSeries =>
      allSeries.where((s) => s.published).toList(growable: false);

  static AchievementSeriesDefinition? seriesById(String id) {
    for (final series in allSeries) {
      if (series.id == id) return series;
    }
    return null;
  }

  static AchievementTierDefinition? tierById(String tierId) {
    for (final series in allSeries) {
      final tier = series.tierById(tierId);
      if (tier != null) return tier;
    }
    return null;
  }

  /// Total badge count shown in UI summaries (published series only).
  static int get totalBadgeCount =>
      publishedSeries.fold<int>(0, (sum, s) => sum + s.tiers.length);

  // ── 课程行者：唯一完成课时，终点 500（硬约束）。─────────────────────
  static const _courseJourney = AchievementSeriesDefinition(
    id: courseJourneyId,
    metric: AchievementMetric.uniqueLessonsCompleted,
    titleKey: courseJourneyId,
    descriptionKey: courseJourneyId,
    iconKey: courseJourneyId,
    tiers: [
      AchievementTierDefinition(
        id: 'course_journey_001',
        ordinal: 1,
        target: 1,
        gemReward: 8,
        rarity: AchievementRarity.bronze,
      ),
      AchievementTierDefinition(
        id: 'course_journey_002',
        ordinal: 2,
        target: 10,
        gemReward: 12,
        rarity: AchievementRarity.silver,
      ),
      AchievementTierDefinition(
        id: 'course_journey_003',
        ordinal: 3,
        target: 25,
        gemReward: 18,
        rarity: AchievementRarity.gold,
      ),
      AchievementTierDefinition(
        id: 'course_journey_004',
        ordinal: 4,
        target: 50,
        gemReward: 25,
        rarity: AchievementRarity.emerald,
      ),
      AchievementTierDefinition(
        id: 'course_journey_005',
        ordinal: 5,
        target: 100,
        gemReward: 35,
        rarity: AchievementRarity.ruby,
      ),
      AchievementTierDefinition(
        id: 'course_journey_006',
        ordinal: 6,
        target: 250,
        gemReward: 45,
        rarity: AchievementRarity.amethyst,
      ),
      AchievementTierDefinition(
        id: 'course_journey_007',
        ordinal: 7,
        target: 500,
        gemReward: 60,
        rarity: AchievementRarity.diamond,
        cosmeticRewardId: cosmeticTitleFarWalker,
      ),
    ],
  );

  // ── 完美主义者：唯一完美课时，终点 100（硬约束）。───────────────────
  static const _perfectJourney = AchievementSeriesDefinition(
    id: perfectJourneyId,
    metric: AchievementMetric.uniquePerfectLessons,
    titleKey: perfectJourneyId,
    descriptionKey: perfectJourneyId,
    iconKey: perfectJourneyId,
    tiers: [
      AchievementTierDefinition(
        id: 'perfect_journey_001',
        ordinal: 1,
        target: 1,
        gemReward: 8,
        rarity: AchievementRarity.bronze,
      ),
      AchievementTierDefinition(
        id: 'perfect_journey_002',
        ordinal: 2,
        target: 5,
        gemReward: 12,
        rarity: AchievementRarity.silver,
      ),
      AchievementTierDefinition(
        id: 'perfect_journey_003',
        ordinal: 3,
        target: 10,
        gemReward: 18,
        rarity: AchievementRarity.gold,
      ),
      AchievementTierDefinition(
        id: 'perfect_journey_004',
        ordinal: 4,
        target: 20,
        gemReward: 25,
        rarity: AchievementRarity.emerald,
      ),
      AchievementTierDefinition(
        id: 'perfect_journey_005',
        ordinal: 5,
        target: 50,
        gemReward: 45,
        rarity: AchievementRarity.amethyst,
      ),
      AchievementTierDefinition(
        id: 'perfect_journey_006',
        ordinal: 6,
        target: 100,
        gemReward: 60,
        rarity: AchievementRarity.diamond,
        cosmeticRewardId: cosmeticTitleHundredFlawless,
      ),
    ],
  );

  // ── 烈焰不息：连续学习天数，终点 365。──────────────────────────────
  static const _streakJourney = AchievementSeriesDefinition(
    id: streakJourneyId,
    metric: AchievementMetric.currentStreakDays,
    titleKey: streakJourneyId,
    descriptionKey: streakJourneyId,
    iconKey: streakJourneyId,
    tiers: [
      AchievementTierDefinition(
        id: 'streak_journey_001',
        ordinal: 1,
        target: 3,
        gemReward: 5,
        rarity: AchievementRarity.sprout,
      ),
      AchievementTierDefinition(
        id: 'streak_journey_002',
        ordinal: 2,
        target: 7,
        gemReward: 8,
        rarity: AchievementRarity.bronze,
      ),
      AchievementTierDefinition(
        id: 'streak_journey_003',
        ordinal: 3,
        target: 14,
        gemReward: 12,
        rarity: AchievementRarity.silver,
      ),
      AchievementTierDefinition(
        id: 'streak_journey_004',
        ordinal: 4,
        target: 30,
        gemReward: 18,
        rarity: AchievementRarity.gold,
      ),
      AchievementTierDefinition(
        id: 'streak_journey_005',
        ordinal: 5,
        target: 75,
        gemReward: 25,
        rarity: AchievementRarity.emerald,
      ),
      AchievementTierDefinition(
        id: 'streak_journey_006',
        ordinal: 6,
        target: 125,
        gemReward: 35,
        rarity: AchievementRarity.ruby,
      ),
      AchievementTierDefinition(
        id: 'streak_journey_007',
        ordinal: 7,
        target: 200,
        gemReward: 45,
        rarity: AchievementRarity.amethyst,
      ),
      AchievementTierDefinition(
        id: 'streak_journey_008',
        ordinal: 8,
        target: 365,
        gemReward: 60,
        rarity: AchievementRarity.diamond,
        cosmeticRewardId: cosmeticStreak365,
      ),
    ],
  );

  // ── 经验积累：累计 XP，终点 50,000。取代旧 Winner/Sage 累计部分与隐藏
  //    xp_* 里程碑。───────────────────────────────────────────────────
  static const _xpJourney = AchievementSeriesDefinition(
    id: xpJourneyId,
    metric: AchievementMetric.totalXp,
    titleKey: xpJourneyId,
    descriptionKey: xpJourneyId,
    iconKey: xpJourneyId,
    tiers: [
      AchievementTierDefinition(
        id: 'xp_journey_001',
        ordinal: 1,
        target: 100,
        gemReward: 8,
        rarity: AchievementRarity.bronze,
      ),
      AchievementTierDefinition(
        id: 'xp_journey_002',
        ordinal: 2,
        target: 500,
        gemReward: 12,
        rarity: AchievementRarity.silver,
      ),
      AchievementTierDefinition(
        id: 'xp_journey_003',
        ordinal: 3,
        target: 1000,
        gemReward: 18,
        rarity: AchievementRarity.gold,
      ),
      AchievementTierDefinition(
        id: 'xp_journey_004',
        ordinal: 4,
        target: 5000,
        gemReward: 25,
        rarity: AchievementRarity.emerald,
      ),
      AchievementTierDefinition(
        id: 'xp_journey_005',
        ordinal: 5,
        target: 10000,
        gemReward: 45,
        rarity: AchievementRarity.amethyst,
      ),
      AchievementTierDefinition(
        id: 'xp_journey_006',
        ordinal: 6,
        target: 50000,
        gemReward: 60,
        rarity: AchievementRarity.diamond,
      ),
    ],
  );

  // ── 今日专注：历史单日最高 XP（不是累计 XP）。──────────────────────
  static const _dailyFocus = AchievementSeriesDefinition(
    id: dailyFocusId,
    metric: AchievementMetric.maxDailyXp,
    titleKey: dailyFocusId,
    descriptionKey: dailyFocusId,
    iconKey: dailyFocusId,
    tiers: [
      AchievementTierDefinition(
        id: 'daily_focus_001',
        ordinal: 1,
        target: 50,
        gemReward: 8,
        rarity: AchievementRarity.bronze,
      ),
      AchievementTierDefinition(
        id: 'daily_focus_002',
        ordinal: 2,
        target: 100,
        gemReward: 12,
        rarity: AchievementRarity.silver,
      ),
      AchievementTierDefinition(
        id: 'daily_focus_003',
        ordinal: 3,
        target: 250,
        gemReward: 18,
        rarity: AchievementRarity.gold,
      ),
      AchievementTierDefinition(
        id: 'daily_focus_004',
        ordinal: 4,
        target: 500,
        gemReward: 25,
        rarity: AchievementRarity.emerald,
      ),
      AchievementTierDefinition(
        id: 'daily_focus_005',
        ordinal: 5,
        target: 1000,
        gemReward: 45,
        rarity: AchievementRarity.amethyst,
      ),
      AchievementTierDefinition(
        id: 'daily_focus_006',
        ordinal: 6,
        target: 2000,
        gemReward: 60,
        rarity: AchievementRarity.diamond,
      ),
    ],
  );

  // ── 复习达人：累计正式提交的复习卡片作答数（按卡计，不按场次计）。
  //    覆盖 Turna SRS、语法复习与 Anki 正式复习。────────────────────
  static const _reviewJourney = AchievementSeriesDefinition(
    id: reviewJourneyId,
    metric: AchievementMetric.totalReviewedCards,
    titleKey: reviewJourneyId,
    descriptionKey: reviewJourneyId,
    iconKey: reviewJourneyId,
    tiers: [
      AchievementTierDefinition(
        id: 'review_journey_001',
        ordinal: 1,
        target: 10,
        gemReward: 8,
        rarity: AchievementRarity.bronze,
      ),
      AchievementTierDefinition(
        id: 'review_journey_002',
        ordinal: 2,
        target: 50,
        gemReward: 12,
        rarity: AchievementRarity.silver,
      ),
      AchievementTierDefinition(
        id: 'review_journey_003',
        ordinal: 3,
        target: 200,
        gemReward: 18,
        rarity: AchievementRarity.gold,
      ),
      AchievementTierDefinition(
        id: 'review_journey_004',
        ordinal: 4,
        target: 500,
        gemReward: 25,
        rarity: AchievementRarity.emerald,
      ),
      AchievementTierDefinition(
        id: 'review_journey_005',
        ordinal: 5,
        target: 1000,
        gemReward: 45,
        rarity: AchievementRarity.amethyst,
      ),
      AchievementTierDefinition(
        id: 'review_journey_006',
        ordinal: 6,
        target: 5000,
        gemReward: 60,
        rarity: AchievementRarity.diamond,
      ),
    ],
  );

  // ── 词海拾贝：唯一学习词条。延迟发布（published=false）：旧日志不携带
  //    wordIds，投影器尚未覆盖全部正式学习路径；发布前不评估、不展示。
  //    不再读取没有生产写入者的旧 wordsLearned 计数器。────────────────
  static const _vocabularyJourney = AchievementSeriesDefinition(
    id: vocabularyJourneyId,
    metric: AchievementMetric.uniqueWordsStudied,
    titleKey: vocabularyJourneyId,
    descriptionKey: vocabularyJourneyId,
    iconKey: vocabularyJourneyId,
    published: false,
    tiers: [
      AchievementTierDefinition(
        id: 'vocabulary_journey_001',
        ordinal: 1,
        target: 10,
        gemReward: 8,
        rarity: AchievementRarity.bronze,
      ),
      AchievementTierDefinition(
        id: 'vocabulary_journey_002',
        ordinal: 2,
        target: 25,
        gemReward: 12,
        rarity: AchievementRarity.silver,
      ),
      AchievementTierDefinition(
        id: 'vocabulary_journey_003',
        ordinal: 3,
        target: 50,
        gemReward: 18,
        rarity: AchievementRarity.gold,
      ),
      AchievementTierDefinition(
        id: 'vocabulary_journey_004',
        ordinal: 4,
        target: 100,
        gemReward: 25,
        rarity: AchievementRarity.emerald,
      ),
      AchievementTierDefinition(
        id: 'vocabulary_journey_005',
        ordinal: 5,
        target: 250,
        gemReward: 35,
        rarity: AchievementRarity.ruby,
      ),
      AchievementTierDefinition(
        id: 'vocabulary_journey_006',
        ordinal: 6,
        target: 500,
        gemReward: 45,
        rarity: AchievementRarity.amethyst,
      ),
      AchievementTierDefinition(
        id: 'vocabulary_journey_007',
        ordinal: 7,
        target: 1000,
        gemReward: 60,
        rarity: AchievementRarity.diamond,
      ),
    ],
  );
}
