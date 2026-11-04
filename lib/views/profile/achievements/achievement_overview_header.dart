// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/domain/achievements/achievement_state.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/achievements/achievement_ui_catalog.dart';
import 'package:turna/views/widgets/report_kit.dart';
import 'package:turna/core/theme.dart';

/// 完成度开篇（湿地雾光 R15）：报告构图的指标头 —— 完成度百分数为大数字，
/// 已获得数为副行。暖沙 / 陶土是成就域的衬底色相（ADR 0062）。
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

    return ReportMetricHeader(
      label: AppStrings.achievementsOverviewTitle,
      value: AppStrings.achievementsCompletionPercent(percent),
      caption: AppStrings.achievementsOverviewCount(unlockedCount, totalCount),
      accentColor: TurnaTheme.anatolianClay,
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
    final ratio = nextTarget > 0
        ? (progress.currentProgress / nextTarget).clamp(0.0, 1.0)
        : 0.0;

    return Material(
      // ADR 0062：用该成就系列自己的色相做均匀淡彩实面（同徽章卡：
      // 网格里的小卡不铺渐变与彩影）。
      color: TurnaTheme.glassSolid(context, accent, level: GlassLevel.l1),
      borderRadius: BorderRadius.circular(TurnaTheme.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TurnaTheme.cardRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TurnaTheme.cardRadius),
            border: Border.all(
              color: TurnaTheme.glassStroke(
                context,
                accent,
                level: GlassLevel.l1,
              ),
            ),
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
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(TurnaTheme.radiusRound),
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
              Flexible(
                child: Text(
                  AppStrings.achievementsTierProgress(
                    progress.currentProgress,
                    nextTarget,
                  ),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
