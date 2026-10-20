// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/practice/ai_practice_job_queue.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/ai/components/ai_practice_actions.dart';
import 'package:turna/views/ai/components/ai_practice_card.dart';
import 'package:turna/views/ai/components/ai_practice_job_banner.dart';
import 'package:turna/views/play/components/play_tiles.dart';

/// "我的练习" block embedded in the AI Hub: running job + latest three drafts.
class AiPracticeLibrarySection extends StatefulWidget {
  const AiPracticeLibrarySection({super.key, required this.onGenerate});

  final VoidCallback onGenerate;

  @override
  State<AiPracticeLibrarySection> createState() =>
      _AiPracticeLibrarySectionState();
}

class _AiPracticeLibrarySectionState extends State<AiPracticeLibrarySection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        context.read<AiPracticeJobQueue>().ensureLoaded();
      } catch (_) {
        // Optional dependency: hub widget tests pump without the queue.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Optional dependency: hub widget tests pump a reduced provider stack.
    final AiPracticeJobQueue queue;
    try {
      queue = context.watch<AiPracticeJobQueue>();
    } catch (_) {
      return const SizedBox.shrink();
    }
    final active = queue.activeJob;
    // Preview = favourites first, then whatever is about to expire. Jobs are
    // counted, not listed: mixing "生成失败" rows into "我的练习" made the block
    // read like content when it was only a task log.
    final preview = queue.hubPreview(limit: 3);
    final taskCount = queue.tasks.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionTitle(title: AppStrings.aiPracticeSectionTitle),
              ),
              if (queue.items.isNotEmpty)
                TextButton(
                  onPressed: () =>
                      context.router.push(const AiPracticeLibraryRoute()),
                  child: Text(AppStrings.aiPracticeViewAll),
                ),
            ],
          ),
          if (active != null) ...[
            AiPracticeJobBanner(
              job: active,
              onCancel: () => cancelAiPractice(context, active),
              onOpen: () => context.router.push(const AiPracticeLibraryRoute()),
            ),
            const SizedBox(height: 10),
          ],
          if (queue.items.isEmpty)
            SoftCard(
              accentColor: TurnaTheme.brandTeal,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.aiPracticeSectionEmpty,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textSecondaryColor(context),
                            height: 1.5,
                          ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: widget.onGenerate,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text(AppStrings.aiPracticeGenerateTitle),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            for (var i = 0; i < preview.length; i++) ...[
              AiPracticeCard(
                item: preview[i],
                onStart: () => openAiPractice(context, preview[i]),
                onPin: () => togglePin(context, preview[i], pinned: true),
                onUnpin: () => togglePin(context, preview[i], pinned: false),
                onAdjust: () => adjustAiPractice(context, preview[i]),
                onDetail: () => context.router.push(
                  AiPracticeDetailRoute(courseId: preview[i].id),
                ),
                onDelete: () => deleteAiPractices(context, [preview[i]]),
                onRetry: () => retryAiPractice(context, preview[i]),
                onCancel: () => cancelAiPractice(context, preview[i]),
              ),
              if (i < preview.length - 1) const SizedBox(height: 8),
            ],
            if (taskCount > 0) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () =>
                    context.router.push(const AiPracticeLibraryRoute()),
                borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hourglass_bottom_rounded,
                        size: 16,
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${AppStrings.aiPracticeGroupTasks} · $taskCount',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: TurnaTheme.textSecondaryColor(context),
                            ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
