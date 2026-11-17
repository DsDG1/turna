// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/domain/achievements/achievement_catalog.dart';
import 'package:turna/domain/achievements/achievement_definition.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/core/theme.dart';

/// UI-layer resolver for achievement presentation: icons, colors, localized
/// strings, and progress units. The domain layer stays free of Flutter
/// assets; everything visual is mapped here from `iconKey` / series id /
/// rarity.
class AchievementUiCatalog {
  const AchievementUiCatalog._();

  // Achievement accent palette — deliberately distinct from the league
  // tokens (softer hues picked for badge legibility on light & dark
  // surfaces). Tokens live in TurnaTheme.
  static const Color _dailyFocusGold = TurnaTheme.achievementGold;
  static const Color _vocabularyBlue = TurnaTheme.achievementSky;
  static const Color _sproutGreen = TurnaTheme.achievementSage;
  static const Color _silverGray = TurnaTheme.achievementSlate;
  static const Color _emeraldGreen = TurnaTheme.achievementEmerald;
  static const Color _rubyRed = TurnaTheme.achievementCrimson;
  static const Color _diamondBlue = TurnaTheme.achievementCyan;

  static IconData iconFor(String iconKey) {
    switch (iconKey) {
      case AchievementCatalog.courseJourneyId:
        return Icons.explore_rounded;
      case AchievementCatalog.perfectJourneyId:
        return Icons.track_changes_rounded;
      case AchievementCatalog.streakJourneyId:
        return Icons.local_fire_department_rounded;
      case AchievementCatalog.xpJourneyId:
        return Icons.bolt_rounded;
      case AchievementCatalog.dailyFocusId:
        return Icons.wb_sunny_rounded;
      case AchievementCatalog.reviewJourneyId:
        return Icons.style_rounded;
      case AchievementCatalog.vocabularyJourneyId:
        return Icons.auto_stories_rounded;
      default:
        return Icons.military_tech_rounded;
    }
  }

  /// Series accent color. Achievements use the clay family (ADR 0033) plus
  /// per-series accents that stay readable in both themes.
  static Color colorFor(String seriesId) {
    switch (seriesId) {
      case AchievementCatalog.courseJourneyId:
        return TurnaTheme.brandTeal;
      case AchievementCatalog.perfectJourneyId:
        return TurnaTheme.anatolianClay;
      case AchievementCatalog.streakJourneyId:
        return TurnaTheme.warning;
      case AchievementCatalog.xpJourneyId:
        return TurnaTheme.amethystLeague;
      case AchievementCatalog.dailyFocusId:
        return _dailyFocusGold;
      case AchievementCatalog.reviewJourneyId:
        return TurnaTheme.brandSky;
      case AchievementCatalog.vocabularyJourneyId:
        return _vocabularyBlue;
      default:
        return TurnaTheme.anatolianClay;
    }
  }

  static String titleFor(String titleKey) {
    switch (titleKey) {
      case AchievementCatalog.courseJourneyId:
        return AppStrings.achievementsSeriesCourseJourney;
      case AchievementCatalog.perfectJourneyId:
        return AppStrings.achievementsSeriesPerfectJourney;
      case AchievementCatalog.streakJourneyId:
        return AppStrings.achievementsSeriesStreakJourney;
      case AchievementCatalog.xpJourneyId:
        return AppStrings.achievementsSeriesXpJourney;
      case AchievementCatalog.dailyFocusId:
        return AppStrings.achievementsSeriesDailyFocus;
      case AchievementCatalog.reviewJourneyId:
        return AppStrings.achievementsSeriesReviewJourney;
      case AchievementCatalog.vocabularyJourneyId:
        return AppStrings.achievementsSeriesVocabularyJourney;
      default:
        return titleKey;
    }
  }

  static String descriptionFor(String descriptionKey) {
    switch (descriptionKey) {
      case AchievementCatalog.courseJourneyId:
        return AppStrings.achievementsSeriesCourseJourneyDesc;
      case AchievementCatalog.perfectJourneyId:
        return AppStrings.achievementsSeriesPerfectJourneyDesc;
      case AchievementCatalog.streakJourneyId:
        return AppStrings.achievementsSeriesStreakJourneyDesc;
      case AchievementCatalog.xpJourneyId:
        return AppStrings.achievementsSeriesXpJourneyDesc;
      case AchievementCatalog.dailyFocusId:
        return AppStrings.achievementsSeriesDailyFocusDesc;
      case AchievementCatalog.reviewJourneyId:
        return AppStrings.achievementsSeriesReviewJourneyDesc;
      case AchievementCatalog.vocabularyJourneyId:
        return AppStrings.achievementsSeriesVocabularyJourneyDesc;
      default:
        return descriptionKey;
    }
  }

  /// Rarity material color for badge rings / glows. Locked badges render as
  /// outlines regardless of rarity.
  static Color rarityColor(AchievementRarity rarity) {
    switch (rarity) {
      case AchievementRarity.sprout:
        return _sproutGreen;
      case AchievementRarity.bronze:
        return TurnaTheme.leagueBronze;
      case AchievementRarity.silver:
        return _silverGray;
      case AchievementRarity.gold:
        return TurnaTheme.leagueGold;
      case AchievementRarity.emerald:
        return _emeraldGreen;
      case AchievementRarity.ruby:
        return _rubyRed;
      case AchievementRarity.amethyst:
        return TurnaTheme.leagueAmethyst;
      case AchievementRarity.diamond:
        return _diamondBlue;
    }
  }

  static String unitFor(AchievementMetric metric) {
    switch (metric) {
      case AchievementMetric.uniqueLessonsCompleted:
        return AppStrings.achievementsUnitLessons;
      case AchievementMetric.uniquePerfectLessons:
        return AppStrings.achievementsUnitLessons;
      case AchievementMetric.currentStreakDays:
        return AppStrings.achievementsUnitDays;
      case AchievementMetric.totalXp:
        return AppStrings.achievementsUnitXp;
      case AchievementMetric.maxDailyXp:
        return AppStrings.achievementsUnitXp;
      case AchievementMetric.totalReviewedCards:
        return AppStrings.achievementsUnitCards;
      case AchievementMetric.uniqueWordsStudied:
        return AppStrings.achievementsUnitWords;
    }
  }

  /// Cosmetic reward display label (titles / rings). Returns null for tiers
  /// without a commemorative reward.
  static String? cosmeticLabel(String? cosmeticRewardId) {
    switch (cosmeticRewardId) {
      case AchievementCatalog.cosmeticTitleFarWalker:
        return AppStrings.achievementsCosmeticTitleFarWalker;
      case AchievementCatalog.cosmeticTitleHundredFlawless:
        return AppStrings.achievementsCosmeticTitleHundredFlawless;
      case AchievementCatalog.cosmeticStreak365:
        return AppStrings.achievementsCosmeticStreak365;
      default:
        return null;
    }
  }
}
