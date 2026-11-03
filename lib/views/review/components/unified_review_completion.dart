import 'package:flutter/material.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/achievements/achievement_feedback_banner.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/cosmetic_completion_badge.dart';
import 'package:turna/views/widgets/report_kit.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_geometry.dart';
import 'package:turna/views/widgets/turna_page_content.dart';

/// Unified review completion summary screen.
///
/// 「湿地雾光」R08 收敛：**几何完成标记 + 结果一行 + 收获纵向 + 单一下一步**。
/// 不再用屏高弹层堆叠——完成是一种页面语言：拱形几何标记成就语义，结果用
/// 一行文字交代，收获（经验 / 宝石 / 成就）纵向排列，下一步只有一个主操作
/// （还有到期批次时是「继续复习」，否则是「完成」）。
class UnifiedReviewCompletion extends StatelessWidget {
  final int totalCount;
  final int rememberedCount;
  final int forgottenCount;
  final Duration elapsed;
  final int xpEarned;
  final int gemsEarned;
  final int remainingDue;
  final VoidCallback? onReviewMore;
  final VoidCallback? onUndoLast;
  final VoidCallback onFinish;

  const UnifiedReviewCompletion({
    super.key,
    required this.totalCount,
    required this.rememberedCount,
    required this.forgottenCount,
    required this.elapsed,
    this.xpEarned = 15,
    this.gemsEarned = 5,
    this.remainingDue = 0,
    this.onReviewMore,
    this.onUndoLast,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final hasMore = remainingDue > 0 && onReviewMore != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: TurnaPageContent(
        maxWidth: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 几何完成标记（拱形 · 成就语义） ──────────────────────
            const TurnaGeometry(
              kind: TurnaGeometryKind.achievement,
              size: 132,
              child: CosmeticCompletionBadge(
                fallbackIcon: Icons.check_circle_rounded,
                fallbackColor: TurnaTheme.brandTeal,
                iconSize: 48,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              AppStrings.reviewCompletionTitle,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
            ),

            // ── 结果一行 ────────────────────────────────────────────
            const SizedBox(height: 8),
            Text(
              AppStrings.reviewCompletionResultLine(
                totalCount,
                rememberedCount,
                forgottenCount,
              ),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),

            // ── 收获纵向（经验 / 宝石 / 本场成就） ───────────────────
            const SizedBox(height: 32),
            if (xpEarned > 0 || gemsEarned > 0)
              ReportDefinitionList(
                rows: [
                  if (xpEarned > 0)
                    ReportDefinitionRow(
                      label: AppStrings.lessonXp,
                      value: '+$xpEarned',
                    ),
                  if (gemsEarned > 0)
                    ReportDefinitionRow(
                      label: AppStrings.lessonGems,
                      value: '+$gemsEarned',
                    ),
                ],
              ),
            // Achievement unlocks from this review session surface here,
            // in the same completion surface as the XP / gem rewards.
            const AchievementFeedbackBanner(),
            if (onUndoLast != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onUndoLast,
                icon: const Icon(Icons.undo_rounded),
                label: Text(AppStrings.reviewUndoLastCard),
              ),
            ],
            if (remainingDue > 0) ...[
              const SizedBox(height: 8),
              Text(
                AppStrings.reviewRemainingDue(remainingDue),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
              ),
            ],

            // ── 单一下一步 ──────────────────────────────────────────
            const SizedBox(height: 24),
            SessionPrimaryAction(
              label: hasMore
                  ? AppStrings.reviewContinueBatch
                  : AppStrings.commonDone,
              onPressed: hasMore ? onReviewMore : onFinish,
              trailingIcon:
                  hasMore ? Icons.play_arrow_rounded : Icons.check_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
