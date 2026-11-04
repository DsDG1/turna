// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_tutor_chat_session.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/lesson/components/ai_depth_tutor_sheet.dart';
import 'package:turna/views/widgets/directory_rows.dart';
import 'package:turna/views/widgets/turna_sheet.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_page_content.dart';
import 'package:turna/views/ai/components/ai_explain_prefs_card.dart';
import 'package:turna/views/ai/components/ai_generated_notice.dart';
import 'package:turna/views/ai/components/ai_practice_library_section.dart';
import 'package:turna/views/ai/components/ai_practice_generate_sheet.dart';
import 'package:turna/views/ai/ai_prompt_sheet.dart';
import 'package:turna/core/theme.dart';

/// Centralized AI surface (Phase 2.3 / Phase 3 of floofy-hugging-hopper).
///
/// 「湿地雾光」R14 口径：AI 大厅 = **任务目录**，不再是大卡堆叠——
///   1. **引擎状态一行**：状态点 + 一句文案（[AiEngineConfigHolder] 快照），
///      点按进连接页；未配置时首屏给「连接 AI」主行动（[SessionPrimaryAction]）。
///   2. **继续** —— 最近三件可续 AI 任务，行式（发丝线）。
///   3. **生成练习 / 伴学** —— 每个 AI 能力是 [DirectoryLinkRow] 式入口
///      （图标井 + 标题 + 一句说明）。
///   4. **讲解偏好 / 系统提示词** —— 偏好目录表单与链接入口。
///
/// 生成物不直接写课程树：它们先进入「我的练习」（[AiPracticeLibrarySection]），
/// 生成任务由 app 级队列承载，切页不中断。
@RoutePage()
class AiHubPage extends StatelessWidget {
  const AiHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.surfaceColor(context),
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: TurnaTheme.brandTeal,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              AppStrings.playSmartPracticeTitle,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: AppStrings.aiFeatureGuideTooltip,
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => context.router.push(const AiFeatureGuideRoute()),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: TurnaPageContent(
          maxWidth: AppSpacing.formColumnMaxWidth,
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              // 引擎状态一行化：状态点 + 文案 + chevron，点按进连接页。
              // 未配置时的页面级主行动紧随其后。
              const SliverToBoxAdapter(child: _EngineStatusLine()),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.pageMargin,
                  AppSpacing.md,
                  AppSpacing.pageMargin,
                  0,
                ),
                sliver: SliverToBoxAdapter(child: _ConnectCta()),
              ),
              // AI 助手入口的**页面级**显式标识：用户在产生第一轮输出之前
              // 就知道这里的内容是模型生成的。单条输出的角标另由
              // AiMarkdownBody 承担。
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.pageMargin,
                  AppSpacing.md,
                  AppSpacing.pageMargin,
                  0,
                ),
                sliver: SliverToBoxAdapter(child: AiGeneratedBanner()),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
              SliverToBoxAdapter(
                child: AiPracticeLibrarySection(
                  onGenerate: () => showAiPracticeGenerateSheet(context),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
              const SliverToBoxAdapter(child: _GenerateSection()),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
              const SliverToBoxAdapter(child: _ContinueSection()),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
              const SliverToBoxAdapter(child: _CompanionSection()),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
              const SliverToBoxAdapter(child: AiExplainPrefsCard()),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
              // 系统提示词：把「AI 到底被交代了什么」摊开给用户看，并允许在
              // 默认文本之后追加自己的要求（默认部分不可替换）。
              SliverToBoxAdapter(
                child: DirectoryLinkRow(
                  icon: Icons.code_rounded,
                  iconTone: TurnaTheme.brandReed,
                  title: AppStrings.aiHubOpenPromptSheet,
                  description: AppStrings.aiHubOpenPromptSheetSubtitle,
                  onTap: () => showAiPromptSheet(context),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Engine status（一行，不再是渐变大卡）─────────────────────────────────

/// 引擎状态快照：只有这一行消费 holder，未配置态还驱动首屏主行动。
class _EngineStatusSnapshot {
  const _EngineStatusSnapshot({
    required this.complete,
    required this.statusText,
  });

  final bool complete;
  final String statusText;

  @override
  bool operator ==(Object other) =>
      other is _EngineStatusSnapshot &&
      other.complete == complete &&
      other.statusText == statusText;

  @override
  int get hashCode => Object.hash(complete, statusText);
}

class _EngineStatusLine extends StatelessWidget {
  const _EngineStatusLine();

  @override
  Widget build(BuildContext context) {
    return Selector<AiEngineConfigHolder, _EngineStatusSnapshot>(
      selector: (_, holder) => _EngineStatusSnapshot(
        complete: holder.config.isComplete,
        statusText: holder.config.isComplete
            ? AppStrings.aiHubEngineReady(
                holder.config.preset.label,
                holder.config.modelChat,
              )
            : AppStrings.playAiEngineNotConfigured,
      ),
      builder: (context, snap, _) {
        return InkWell(
          onTap: () => _openConfig(context),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageMargin,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: TurnaTheme.dividerBg(context)),
              ),
            ),
            child: Row(
              children: [
                // 状态点：实心 teal = 已连接；空心环 = 未配置（轮廓表达，不靠色盲可辨的色相）。
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: snap.complete ? TurnaTheme.brandTeal : null,
                    border: snap.complete
                        ? null
                        : Border.all(
                            color: TurnaTheme.warning,
                            width: 2,
                          ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
                  child: Text(
                    '${AppStrings.aiHubEngineStatusLabel} · ${snap.statusText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.captionSm(context).copyWith(
                      color: snap.complete
                          ? TurnaTheme.textSecondaryColor(context)
                          : TurnaTheme.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 未配置时的首屏主行动；已配置时不渲染（大厅不再放「去配置」卡）。
class _ConnectCta extends StatelessWidget {
  const _ConnectCta();

  @override
  Widget build(BuildContext context) {
    return Selector<AiEngineConfigHolder, bool>(
      selector: (_, holder) => holder.config.isComplete,
      builder: (context, complete, _) {
        if (complete) return const SizedBox.shrink();
        return SessionPrimaryAction(
          label: AppStrings.aiHubConnectCta,
          onPressed: () => _openConfig(context),
          trailingIcon: Icons.arrow_forward_rounded,
        );
      },
    );
  }
}

// ─── 生成练习（目录入口）──────────────────────────────────────────────────

class _GenerateSection extends StatelessWidget {
  const _GenerateSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(AppStrings.aiHubNew),
        // Primary: 用学习数据或自定义主题生成一份练习/课程草稿。生成在
        // app 级后台队列里跑，关掉面板后仍继续；结果进入「我的练习」。
        DirectoryLinkRow(
          icon: Icons.history_toggle_off_rounded,
          iconTone: TurnaTheme.brandTeal,
          title: AppStrings.aiPracticeEntryDataTitle,
          description: AppStrings.aiPracticeEntryDataSubtitle,
          onTap: () => showAiPracticeGenerateSheet(context),
        ),
        DirectoryLinkRow(
          icon: Icons.school_rounded,
          iconTone: TurnaTheme.anatolianClay,
          title: AppStrings.aiPracticeModeCustom,
          description: AppStrings.aiPracticeEntryCustomSubtitle,
          onTap: () => showAiPracticeGenerateSheet(context, customMode: true),
        ),
      ],
    );
  }
}

// ─── 继续（最近任务，行式）────────────────────────────────────────────────

class _ContinueSection extends StatelessWidget {
  const _ContinueSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(AppStrings.aiHubContinue),
        Selector<AiRecentTasksProvider, List<AiRecentTask>>(
          selector: (_, p) => p.items,
          builder: (context, items, _) {
            // Newest-first snapshot; slice here instead of in the selector
            // so the selected value keeps a stable identity between
            // mutations (a slicing selector would allocate on every
            // evaluation and rebuild on every notify).
            final top =
                items.where(_isResumable).take(3).toList(growable: false);
            if (top.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  AppStrings.aiHubContinueEmpty,
                  style: AppTextStyles.captionSm(context).copyWith(
                    color: TurnaTheme.textHintColor(context),
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < top.length; i++) ...[
                  _RecentRow(
                    task: top[i],
                    showDivider: i < top.length - 1,
                    onTap: top[i].route == null
                        ? null
                        : () => _navigateByRoute(context, top[i].route!),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  static bool _isResumable(AiRecentTask task) {
    return isAiTaskResumable(
      task,
      tutorChatHasSession: AiTutorChatSessionStore().hasSession,
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.task, this.onTap, this.showDivider = true});

  final AiRecentTask task;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return DirectoryEntryRow(
      title: task.summary,
      subtitle: _labelFor(task.kind),
      onTap: onTap,
      showDivider: showDivider,
    );
  }

  static String _labelFor(String kind) {
    switch (kind) {
      case AiTaskKind.wish:
        return AppStrings.aiTaskLabelWish;
      case AiTaskKind.textbook:
        return AppStrings.aiTaskLabelTextbook;
      case AiTaskKind.tutorMistakes:
        return AppStrings.aiTaskLabelTutorMistakes;
      case AiTaskKind.tutorWeakWords:
        return AppStrings.aiTaskLabelTutorWeak;
      case AiTaskKind.hintChat:
        return AppStrings.aiTaskLabelHintChat;
      case AiTaskKind.hintDepth:
        return AppStrings.aiTaskLabelDepth;
      case AiTaskKind.lessonHelper:
        return AppStrings.aiTaskLabelLessonHelper;
      case AiTaskKind.courseGenerate:
        return AppStrings.aiTaskLabelCourseGenerate;
      case AiTaskKind.tutorChat:
        return AppStrings.aiGuideFreeChatTitle;
      case AiTaskKind.diagnosis:
        return AppStrings.aiGuideDiagnosisTitle;
      case AiTaskKind.dictionary:
        return AppStrings.aiTaskLabelDictionary;
      default:
        return kind;
    }
  }
}

// ─── 伴学（目录入口）──────────────────────────────────────────────────────

class _CompanionSection extends StatelessWidget {
  const _CompanionSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(AppStrings.aiHubCompanionSection),
        DirectoryLinkRow(
          icon: Icons.chat_bubble_outline_rounded,
          iconTone: TurnaTheme.brandTeal,
          title: AppStrings.aiHubStartTutorChat,
          description: AppStrings.aiHubFreeChatDesc,
          onTap: () => context.router.push(AiTutorChatRoute()),
        ),
        DirectoryLinkRow(
          icon: Icons.analytics_outlined,
          iconTone: TurnaTheme.brandSky,
          title: AppStrings.aiHubStartDiagnosis,
          description: AppStrings.aiHubDiagnosisDesc,
          onTap: () => context.router.push(const AiDiagnosisRoute()),
        ),
        DirectoryLinkRow(
          icon: Icons.bookmark_outline_rounded,
          iconTone: TurnaTheme.anatolianClay,
          title: AppStrings.aiHubStartSaved,
          description: AppStrings.aiHubSavedDesc,
          onTap: () => context.router.push(const AiSavedListRoute()),
        ),
        DirectoryLinkRow(
          icon: Icons.account_tree_outlined,
          iconTone: TurnaTheme.brandReed,
          title: AppStrings.aiHubStartDepthTutor,
          description: AppStrings.aiHubDepthTutorDesc,
          onTap: () => _openSheet(context),
        ),
      ],
    );
  }
}

/// 区块标题：目录页的分组名（排版 + 发丝线组织，不包卡）。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.pageMargin,
        right: AppSpacing.pageMargin,
        bottom: AppSpacing.xs + 2,
      ),
      child: Text(title, style: AppTextStyles.sectionTitle(context)),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────

/// 深度讲解 sheet 走全局弹层容器（R18：拖手 / 标题 / 副题 / 关闭统一，
/// 键盘由 showTurnaSheet 让位）。
Future<void> _openSheet(BuildContext context) {
  return showTurnaSheet(
    context: context,
    title: AppStrings.aiDepthTutorTitle,
    subtitle: AppStrings.aiDepthTutorSubtitle,
    body: const AiDepthTutorSheet(),
  );
}

/// Open the standalone AI API config page.
void _openConfig(BuildContext context) {
  context.router.push(const AiApiConfigRoute());
}

/// Open the feature a recorded AI Hub task points to. Exhaustive over
/// [AiRecentTaskRoute]: adding a destination forces this switch (and its
/// recorded kind) to be handled at compile time.
void _navigateByRoute(BuildContext context, AiRecentTaskRoute route) {
  switch (route) {
    case AiRecentTaskRoute.textbookImport:
      context.router.push(const TextbookImportRoute());
    case AiRecentTaskRoute.tutorChat:
      context.router.push(AiTutorChatRoute());
    case AiRecentTaskRoute.diagnosis:
      context.router.push(const AiDiagnosisRoute());
    case AiRecentTaskRoute.hintChat:
      context.router.push(AiHintChatRoute());
  }
}
