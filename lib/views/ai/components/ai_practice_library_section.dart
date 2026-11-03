// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/practice/ai_practice_job_queue.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/ai/components/ai_practice_actions.dart';
import 'package:turna/views/ai/components/ai_practice_card.dart';
import 'package:turna/views/ai/components/ai_practice_job_banner.dart';

/// "我的练习" block embedded in the AI Hub —— 目录化（R14）：
///
/// 区块标题 + 行；五态（未配置 / 空库 / 排队 / 生成中 / 失败）全部行内表达，
/// 不再各占一卡：
///   * 未配置且空库 → 一行提示文案（连接入口由页首「连接 AI」主行动承担）；
///   * 空库 → 一行引导文案 + 文字链「生成练习」；
///   * 排队 / 生成中 → [AiPracticeJobBanner] 一行（含取消）；
///   * 失败 / 待练习 → [AiPracticeCard] 行（状态词与状态符行内）。
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
    // 引擎是否已配置：空库时的文案分流（未配置 → 提示连接；已配置 → 引导生成）。
    // 同样按可选依赖兜底，Hub 测试的缩减 provider 栈里没有 holder。
    bool complete = true;
    try {
      complete = context.watch<AiEngineConfigHolder>().config.isComplete;
    } catch (_) {
      // Optional dependency: fall back to the "configured" wording.
    }
    final active = queue.activeJob;
    // Preview = favourites first, then whatever is about to expire. Jobs are
    // counted, not listed: mixing "生成失败" rows into "我的练习" made the block
    // read like content when it was only a task log.
    final preview = queue.hubPreview(limit: 3);
    final taskCount = queue.tasks.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageMargin,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.aiPracticeSectionTitle,
                  style: AppTextStyles.sectionTitle(context),
                ),
              ),
              if (queue.items.isNotEmpty)
                TextButton(
                  onPressed: () =>
                      context.router.push(const AiPracticeLibraryRoute()),
                  child: Text(AppStrings.aiPracticeViewAll),
                ),
            ],
          ),
        ),
        if (active != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageMargin,
            ),
            child: AiPracticeJobBanner(
              job: active,
              onCancel: () => cancelAiPractice(context, active),
              onOpen: () =>
                  context.router.push(const AiPracticeLibraryRoute()),
            ),
          ),
        if (queue.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageMargin,
              vertical: AppSpacing.sm + 2,
            ),
            child: _EmptyHint(
              configured: complete,
              onGenerate: widget.onGenerate,
            ),
          )
        else ...[
          for (var i = 0; i < preview.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageMargin,
              ),
              child: AiPracticeCard(
                item: preview[i],
                showDivider: i < preview.length - 1,
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
            ),
          if (taskCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageMargin,
              ),
              child: InkWell(
                onTap: () =>
                    context.router.push(const AiPracticeLibraryRoute()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hourglass_bottom_rounded,
                        size: 16,
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                      const SizedBox(width: AppSpacing.sm - 2),
                      Text(
                        '${AppStrings.aiPracticeGroupTasks} · $taskCount',
                        style: AppTextStyles.captionSm(context),
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
            ),
        ],
      ],
    );
  }
}

/// 空库 / 未配置的一行提示：一行文案 +（已配置时）文字链入口，不占卡。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.configured, required this.onGenerate});

  final bool configured;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            configured
                ? AppStrings.aiPracticeSectionEmpty
                : AppStrings.aiPracticeLibraryNotConfiguredHint,
            style: AppTextStyles.captionSm(context).copyWith(
              color: TurnaTheme.textHintColor(context),
              height: 1.45,
            ),
          ),
        ),
        if (configured) ...[
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: onGenerate,
            child: Text(AppStrings.aiPracticeGenerateTitle),
          ),
        ],
      ],
    );
  }
}
