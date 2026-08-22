// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/domain/achievements/achievement_state.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/achievements/achievement_ui_catalog.dart';
import 'package:turna/views/theme.dart';

/// Hero overview: owned badge count, total, completion ratio, and the most
/// recent unlock date. Reads exclusively from the persisted v2 state.
class AchievementOverviewHeader extends StatelessWidget {
  final int unlockedCount;
  final int totalCount;
  final DateTime? latestUnlockAt;

  const AchievementOverviewHeader({
    super.key,
    required this.unlockedCount,
    required this.totalCount,
    this.latestUnlockAt,
  });

  @override
  Widget build(BuildContext context) {
    final ratio =
        totalCount > 0 ? (unlockedCount / totalCount).clamp(0.0, 1.0) : 0.0;
    final percent = (ratio * 100).round();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            TurnaTheme.anatolianClay.withValues(alpha: 0.12),
            TurnaTheme.warmSand.withValues(alpha: 0.30),
          ],
        ),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.military_tech_rounded,
                color: TurnaTheme.anatolianClay,
                size: 26,
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.achievementsOverviewTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.achievementsOverviewCount(unlockedCount, totalCount),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: TurnaTheme.anatolianClay,
                ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: TurnaTheme.dividerBg(context),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(TurnaTheme.anatolianClay),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.achievementsCompletionRatio(percent),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textSecondaryColor(context),
                ),
          ),
        ],
      ),
    );
  }
}

/// "距离最近" recommendation: one or two series closest to their next tier.
/// Zero-progress series never occupy recommendation slots.
class AchievementNearestCard extends StatelessWidget {
  final String seriesId;
  final AchievementSeriesProgress progress;
  final int nextTarget;
  final VoidCallback? onTap;

  const AchievementNearestCard({
    super.key,
    required this.seriesId,
    required this.progress,
    required this.nextTarget,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AchievementUiCatalog.colorFor(seriesId);
    final ratio =
        nextTarget > 0 ? (progress.currentProgress / nextTarget).clamp(0.0, 1.0) : 0.0;

    return Material(
      color: TurnaTheme.cardBg(context),
      borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            border: Border.all(color: TurnaTheme.statCardBorder(context)),
          ),
          child: Row(
            children: [
              Icon(
                AchievementUiCatalog.iconFor(seriesId),
                color: accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AchievementUiCatalog.titleFor(seriesId),
                      style:
                          Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 5,
                        backgroundColor: TurnaTheme.dividerBg(context),
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${AppStrings.achievementsTierProgress(
                  progress.currentProgress,
                  nextTarget,
                )}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
