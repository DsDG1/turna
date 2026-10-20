// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/play/components/play_tiles.dart';

/// Compact progress card for the job currently running in the background.
///
/// Shown at the top of the AI Hub while a job is queued/running. The queue is
/// app-level, so this is only a view of work that continues on other tabs.
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
    final label = job.status == AiPracticeStatus.queued
        ? AppStrings.aiPracticeQueued
        : total > 0
            ? AppStrings.aiPracticeProgress(done, total)
            : AppStrings.aiPracticeGenerating;
    return SoftCard(
      accentColor: TurnaTheme.brandTeal,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: TurnaTheme.brandTeal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$label · ${AppStrings.aiPracticeBackgroundHint}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                  ),
                  if (total > 0) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: job.progress,
                        minHeight: 4,
                        backgroundColor:
                            TurnaTheme.brandTeal.withValues(alpha: 0.12),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          TurnaTheme.brandTeal,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: AppStrings.aiPracticeCancel,
              onPressed: onCancel,
              icon: const Icon(Icons.stop_circle_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
