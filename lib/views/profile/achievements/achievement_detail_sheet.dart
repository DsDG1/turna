// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/domain/achievements/achievement_definition.dart';
import 'package:turna/domain/achievements/achievement_state.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/achievements/achievement_badge_card.dart';
import 'package:turna/views/profile/achievements/achievement_ui_catalog.dart';
import 'package:turna/views/theme.dart';

/// Series detail bottom sheet: story, full tier ladder with per-tier
/// target / reward / status, unlock date, next step, and the commemorative
/// final-tier reward preview.
Future<void> showAchievementDetailSheet({
  required BuildContext context,
  required AchievementSeriesDefinition series,
  required AchievementSeriesProgress progress,
  required AchievementService service,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TurnaTheme.scaffoldBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (_, scrollController) => _DetailContent(
        series: series,
        progress: progress,
        service: service,
        scrollController: scrollController,
      ),
    ),
  );
}

class _DetailContent extends StatelessWidget {
  final AchievementSeriesDefinition series;
  final AchievementSeriesProgress progress;
  final AchievementService service;
  final ScrollController scrollController;

  const _DetailContent({
    required this.series,
    required this.progress,
    required this.service,
    required this.scrollController,
  });

  String get _remainingLabel {
    final next = progress.nextTier;
    if (next == null) return '';
    final remaining = next.target - progress.currentProgress;
    switch (series.metric) {
      case AchievementMetric.uniqueLessonsCompleted:
        return AppStrings.achievementsRemainingCourses(remaining);
      case AchievementMetric.uniquePerfectLessons:
        return AppStrings.achievementsRemainingPerfects(remaining);
      case AchievementMetric.currentStreakDays:
        return AppStrings.achievementsRemainingStreakDays(remaining);
      case AchievementMetric.totalXp:
        return AppStrings.achievementsRemainingXp(remaining);
      case AchievementMetric.maxDailyXp:
        return AppStrings.achievementsRemainingDailyXp(remaining);
      case AchievementMetric.totalReviewedCards:
        return AppStrings.achievementsRemainingReviews(remaining);
      case AchievementMetric.uniqueWordsStudied:
        return AppStrings.achievementsRemainingWords(remaining);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AchievementUiCatalog.colorFor(series.id);
    final unit = AchievementUiCatalog.unitFor(series.metric);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: TurnaTheme.dividerBg(context),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            AchievementBadge(
              iconKey: series.iconKey,
              seriesId: series.id,
              nextRarity: progress.nextTier?.rarity,
              completedTiers: progress.completedTierCount,
              status: badgeStatusOf(progress),
              size: 56,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AchievementUiCatalog.titleFor(series.titleKey),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AchievementUiCatalog.descriptionFor(series.descriptionKey),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (progress.nextTier != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            ),
            child: Row(
              children: [
                Icon(Icons.flag_rounded, color: accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${AppStrings.achievementsDetailNextStep} · $_remainingLabel',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: TurnaTheme.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            ),
            child: Row(
              children: [
                const Icon(Icons.emoji_events_rounded,
                    color: TurnaTheme.warning, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppStrings.achievementsStateMaxed,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
        if (series.metric == AchievementMetric.maxDailyXp) ...[
          const SizedBox(height: 8),
          Text(
            '${AppStrings.achievementsPersonalBest}：${progress.currentProgress} ${AppStrings.achievementsUnitXp}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textSecondaryColor(context),
                ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          AppStrings.achievementsDetailTierLadder,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        ...series.tiers.map((tier) {
          final tierState = service.state.tierState(tier.id);
          final unlocked = tierState != null;
          final isCurrentPursuit =
              progress.nextTier?.id == tier.id;
          return _TierRow(
            tier: tier,
            tierState: tierState,
            unit: unit,
            accent: accent,
            highlighted: isCurrentPursuit,
            unlocked: unlocked,
          );
        }),
      ],
    );
  }
}

class _TierRow extends StatelessWidget {
  final AchievementTierDefinition tier;
  final AchievementTierState? tierState;
  final String unit;
  final Color accent;
  final bool highlighted;
  final bool unlocked;

  const _TierRow({
    required this.tier,
    required this.tierState,
    required this.unit,
    required this.accent,
    required this.highlighted,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    final rarityColor = AchievementUiCatalog.rarityColor(tier.rarity);
    final cosmetic =
        AchievementUiCatalog.cosmeticLabel(tier.cosmeticRewardId);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted
            ? accent.withValues(alpha: 0.08)
            : TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: highlighted
              ? accent.withValues(alpha: 0.5)
              : TurnaTheme.statCardBorder(context),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unlocked
                  ? rarityColor.withValues(alpha: 0.85)
                  : Colors.transparent,
              border: Border.all(
                color: unlocked
                    ? rarityColor
                    : TurnaTheme.textHintColor(context).withValues(alpha: 0.5),
              ),
            ),
            child: unlocked
                ? const Icon(Icons.check_rounded,
                    color: Colors.white, size: 18)
                : Icon(
                    Icons.lock_outline_rounded,
                    size: 15,
                    color: TurnaTheme.textHintColor(context),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${tier.rarity.displayName} · ${tier.target} $unit',
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: unlocked
                                      ? TurnaTheme.textPrimaryColor(context)
                                      : TurnaTheme.textSecondaryColor(context),
                                ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tierState?.origin ==
                        AchievementUnlockOrigin.migration) ...[
                      const SizedBox(width: 6),
                      _MiniTag(
                        context: context,
                        text: AppStrings.achievementsMigrationBackfillTag,
                        color: TurnaTheme.textHintColor(context),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  cosmetic != null
                      ? '+${tier.gemReward} ${AppStrings.achievementsGemRewardSuffix} · $cosmetic'
                      : '+${tier.gemReward} ${AppStrings.achievementsGemRewardSuffix}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                ),
                if (unlocked && tierState?.unlockedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${AppStrings.achievementsDetailUnlockedOn} '
                    '${_formatDate(tierState!.unlockedAt)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: TurnaTheme.textHintColor(context),
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _MiniTag extends StatelessWidget {
  final BuildContext context;
  final String text;
  final Color color;

  const _MiniTag({required this.context, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontSize: 10,
            ),
      ),
    );
  }
}
