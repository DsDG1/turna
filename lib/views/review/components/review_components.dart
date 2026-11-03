import 'package:flutter/material.dart';

import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/achievements/achievement_feedback_banner.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/cosmetic_completion_badge.dart';
import 'package:turna/views/widgets/report_kit.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_geometry.dart';
import 'package:turna/views/widgets/turna_page_content.dart';

// 「湿地雾光」R08：ReviewRatingBar（与 BinaryRecallBar 平行的评分条）已由
// SessionRatingBand 取代并退役；本文件只剩语法复习的完成态。

/// Grammar review completion state.
///
/// 与 [UnifiedReviewCompletion] 同一完成语言：几何完成标记 + 结果一行 +
/// 收获纵向 + 单一下一步（还有到期语法点时是「继续复习」，否则是「完成」）。
class ReviewCompletionState extends StatelessWidget {
  final int reviewedCount;
  final int dueCount;
  final int xpEarned;
  final int gemsEarned;
  final VoidCallback onDone;
  final VoidCallback onReviewMore;
  final String title;
  final String completionMessage;

  ReviewCompletionState({
    super.key,
    required this.reviewedCount,
    required this.dueCount,
    required this.xpEarned,
    required this.gemsEarned,
    required this.onDone,
    required this.onReviewMore,
    String? title,
    String? completionMessage,
  })  : title = title ?? AppStrings.reviewCompletionTitle,
        completionMessage =
            completionMessage ?? AppStrings.reviewCompletionMessage;

  @override
  Widget build(BuildContext context) {
    final hasMore = dueCount > 0;

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.reviewGrammarReviewTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          // 定义列表的行内有 Expanded，列宽必须有界（平板上收到 560）。
          child: TurnaPageContent(
            maxWidth: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TurnaGeometry(
                  kind: TurnaGeometryKind.achievement,
                  size: 112,
                  child: CosmeticCompletionBadge(
                    fallbackIcon: Icons.emoji_events_rounded,
                    fallbackColor: TurnaTheme.success,
                    iconSize: 44,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                // 结果一行。
                Text(
                  completionMessage,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                  textAlign: TextAlign.center,
                ),
                if (xpEarned > 0 || gemsEarned > 0) ...[
                  const SizedBox(height: 28),
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
                ],
                const AchievementFeedbackBanner(),
                const SizedBox(height: 24),
                SessionPrimaryAction(
                  label: hasMore
                      ? AppStrings.reviewReviewMore
                      : AppStrings.commonDone,
                  onPressed: hasMore ? onReviewMore : onDone,
                  trailingIcon:
                      hasMore ? Icons.play_arrow_rounded : Icons.check_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
