// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/l10n/app_strings.dart';

/// 后台生成任务的**一行化**进度行（R14：运行中进度一行 + 可取消）。
///
/// 生成队列是 app 级的，这条行只是别处仍在工作的一个视图：spinner + 标题 +
/// 进度文案同行，行尾是取消键；点行进「我的练习」。不再占一张带进度条的卡。
class AiPracticeJobBanner extends StatelessWidget {
  const AiPracticeJobBanner({
    super.key,
    required this.job,
    this.onCancel,
    this.onOpen,
  });

  final AiCourse job;
  final VoidCallback? onCancel;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final total = job.progressTotal;
    final done = job.progressDone;
    final status = job.status == AiPracticeStatus.queued
        ? AppStrings.aiPracticeQueued
        : total > 0
            ? AppStrings.aiPracticeProgress(done, total)
            : AppStrings.aiPracticeGenerating;
    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: TurnaTheme.dividerBg(context)),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: TurnaTheme.brandTeal,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                '${job.title} · $status',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyText(context).copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              tooltip: AppStrings.aiPracticeCancel,
              onPressed: onCancel,
              icon: Icon(
                Icons.stop_circle_outlined,
                size: 20,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
