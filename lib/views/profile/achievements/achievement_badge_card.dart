// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/domain/achievements/achievement_definition.dart';
import 'package:turna/domain/achievements/achievement_state.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/achievements/achievement_ui_catalog.dart';
import 'package:turna/views/theme.dart';

/// Visual badge states rendered by [AchievementBadgeCard].
enum AchievementBadgeStatus { locked, inProgress, unlocked, maxed }

AchievementBadgeStatus badgeStatusOf(AchievementSeriesProgress progress) {
  if (progress.isSeriesComplete) return AchievementBadgeStatus.maxed;
  if (progress.completedTierCount > 0) return AchievementBadgeStatus.unlocked;
  if (progress.currentProgress > 0) return AchievementBadgeStatus.inProgress;
  return AchievementBadgeStatus.locked;
}

/// Series badge + card content for the achievements grid. Reads only the
/// service-provided progress view — it never derives unlock state from raw
/// counters.
class AchievementBadgeCard extends StatelessWidget {
  final AchievementSeriesDefinition series;
  final AchievementSeriesProgress progress;

  /// Fun Lab display-only preview: renders everything as unlocked without
  /// touching the persisted state.
  final bool funPreview;
  final VoidCallback? onTap;

  const AchievementBadgeCard({
    super.key,
    required this.series,
    required this.progress,
    this.funPreview = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status =
        funPreview ? AchievementBadgeStatus.maxed : badgeStatusOf(progress);
    final accent = AchievementUiCatalog.colorFor(series.id);
    final nextTier = progress.nextTier;
    final isNew = !funPreview && progress.hasUnseenUnlock;

    return Semantics(
      button: true,
      label: _semanticsLabel(status, nextTier),
      child: Material(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
              border: Border.all(color: TurnaTheme.statCardBorder(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AchievementBadge(
                      iconKey: series.iconKey,
                      seriesId: series.id,
                      nextRarity: nextTier?.rarity,
                      completedTiers: funPreview
                          ? series.tiers.length
                          : progress.completedTierCount,
                      status: status,
                    ),
                    const Spacer(),
                    if (isNew)
                      _NewTag(accent: accent)
                    else if (funPreview)
                      Text(
                        AppStrings.achievementsFunPreviewBanner,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: TurnaTheme.textHintColor(context)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  AchievementUiCatalog.titleFor(series.titleKey),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (status == AchievementBadgeStatus.maxed || funPreview)
                  Text(
                    AppStrings.achievementsStateMaxed,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                  )
                else if (nextTier != null) ...[
                  _ProgressLine(
                    current: progress.currentProgress,
                    target: nextTier.target,
                    unit: AchievementUiCatalog.unitFor(series.metric),
                    accent: accent,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppStrings.achievementsTierCompleted(
                      progress.completedTierCount,
                      progress.totalTierCount,
                    ),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: TurnaTheme.textHintColor(context),
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _semanticsLabel(
    AchievementBadgeStatus status,
    AchievementTierDefinition? nextTier,
  ) {
    final title = AchievementUiCatalog.titleFor(series.titleKey);
    final statusLabel = switch (status) {
      AchievementBadgeStatus.locked => AppStrings.achievementsStateLocked,
      AchievementBadgeStatus.inProgress => AppStrings.achievementsStateInProgress,
      AchievementBadgeStatus.unlocked => AppStrings.achievementsStateUnlocked,
      AchievementBadgeStatus.maxed => AppStrings.achievementsStateMaxed,
    };
    final next = nextTier == null
        ? ''
        : ', ${AppStrings.achievementsTierProgress(
            progress.currentProgress,
            nextTier.target,
          )}${AchievementUiCatalog.unitFor(series.metric)}';
    return '$title, $statusLabel$next';
  }
}

/// Single badge visual: series icon on a rarity-material base. Locked badges
/// use outline + lock (not alpha-faded color, plan §8.2).
class AchievementBadge extends StatelessWidget {
  final String iconKey;
  final String seriesId;

  /// Rarity of the tier currently being pursued — drives the ring material
  /// so the card shows "what you can earn next".
  final AchievementRarity? nextRarity;
  final int completedTiers;
  final AchievementBadgeStatus status;
  final double size;

  const AchievementBadge({
    super.key,
    required this.iconKey,
    required this.seriesId,
    required this.completedTiers,
    required this.status,
    this.nextRarity,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final rarityColor = AchievementUiCatalog.rarityColor(
      nextRarity ?? AchievementRarity.sprout,
    );
    final isUnlocked =
        status == AchievementBadgeStatus.unlocked ||
            status == AchievementBadgeStatus.maxed;

    if (!isUnlocked) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: TurnaTheme.textHintColor(context).withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Icon(
          Icons.lock_outline_rounded,
          size: size * 0.36,
          color: TurnaTheme.textHintColor(context),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          startAngle: 0,
          endAngle: 3.14 * 2,
          colors: [
            rarityColor.withValues(alpha: 0.85),
            rarityColor.withValues(alpha: 0.45),
            rarityColor.withValues(alpha: 0.85),
          ],
        ),
        border: Border.all(
          color: status == AchievementBadgeStatus.maxed
              ? rarityColor
              : rarityColor.withValues(alpha: 0.7),
          width: 2,
        ),
      ),
      child: Icon(
        AchievementUiCatalog.iconFor(iconKey),
        size: size * 0.46,
        color: Colors.white,
      ),
    );
  }
}

class _NewTag extends StatelessWidget {
  final Color accent;

  const _NewTag({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
      ),
      child: Text(
        AppStrings.achievementsNewBadgeTag,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  final int current;
  final int target;
  final String unit;
  final Color accent;

  const _ProgressLine({
    required this.current,
    required this.target,
    required this.unit,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: TurnaTheme.dividerBg(context),
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${AppStrings.achievementsTierProgress(current, target)} $unit',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: TurnaTheme.textSecondaryColor(context),
                fontWeight: FontWeight.w600,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
