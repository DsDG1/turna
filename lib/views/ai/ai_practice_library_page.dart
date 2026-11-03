// Dart imports:
import 'dart:async';

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
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/ai/components/ai_practice_actions.dart';
import 'package:turna/views/ai/components/ai_practice_card.dart';
import 'package:turna/views/ai/components/ai_practice_generate_sheet.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// Full AI course library, grouped the way the content actually behaves
/// （R14 目录化：区块标题 + 行，发丝线分组）:
///
/// - **收藏** — favourited, permanent;
/// - **草稿** — playable but un-favourited, with a countdown to the automatic
///   sweep (7 days from creation, ADR 0054);
/// - **生成任务** — queued / running / failed jobs, which are *not* content and
///   used to sit mixed into the same flat list.
@RoutePage()
class AiPracticeLibraryPage extends StatefulWidget {
  const AiPracticeLibraryPage({super.key});

  @override
  State<AiPracticeLibraryPage> createState() => _AiPracticeLibraryPageState();
}

class _AiPracticeLibraryPageState extends State<AiPracticeLibraryPage> {
  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final queue = context.read<AiPracticeJobQueue>();
      await queue.ensureLoaded();
      // The 7-day promise has to hold inside a long session too, not just at
      // the next cold start.
      final removed = await queue.sweepExpired();
      if (!mounted || removed <= 0) return;
      TurnaSnackBar.show(
        context,
        AppStrings.aiPracticeSweptOnOpen(removed),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<AiPracticeJobQueue>();
    final items = queue.items;
    // Drop ids that no longer exist (deleted or pruned while selected).
    _selected.removeWhere((id) => !items.any((item) => item.id == id));

    final favorites = queue.favorites;
    final drafts = queue.drafts;
    final tasks = queue.tasks;
    // 未配置且空库：空态直接承担「连接」引导；否则底部主行动是「生成练习」。
    final complete = context.watch<AiEngineConfigHolder>().config.isComplete;

    return Scaffold(
      backgroundColor: TurnaTheme.surfaceColor(context),
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          AppStrings.aiPracticeSectionTitle,
          style: AppTextStyles.cardTitle(context).copyWith(fontSize: 17),
        ),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              key: const Key('ai-practice-select-toggle'),
              onPressed: () => setState(() {
                _selectionMode = !_selectionMode;
                if (!_selectionMode) _selected.clear();
              }),
              child: Text(
                _selectionMode
                    ? AppStrings.aiPracticeExitSelect
                    : AppStrings.aiPracticeSelect,
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: TurnaTheme.brandTeal,
                onRefresh: () => queue.reload(),
                child: items.isEmpty
                    ? _empty(context, complete)
                    : ListView(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        children: [
                          if (favorites.isNotEmpty)
                            ..._group(
                              context,
                              title: AppStrings.aiPracticeGroupFavorites,
                              items: favorites,
                            ),
                          if (drafts.isNotEmpty) ...[
                            if (favorites.isNotEmpty)
                              const SizedBox(height: AppSpacing.xl),
                            ..._group(
                              context,
                              title: AppStrings.aiPracticeGroupDrafts,
                              items: drafts,
                              footnote: AppStrings.aiPracticeExpiryHint,
                            ),
                          ],
                          if (tasks.isNotEmpty) ...[
                            if (favorites.isNotEmpty || drafts.isNotEmpty)
                              const SizedBox(height: AppSpacing.xl),
                            ..._group(
                              context,
                              title: AppStrings.aiPracticeGroupTasks,
                              items: tasks,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                        ],
                      ),
              ),
            ),
            if (_selectionMode && items.isNotEmpty)
              _selectionBar(context, items),
            if (!_selectionMode)
              SessionActionBand(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageMargin,
                  AppSpacing.md,
                  AppSpacing.pageMargin,
                  AppSpacing.lg,
                ),
                child: complete
                    ? SessionPrimaryAction(
                        label: AppStrings.aiPracticeGenerateTitle,
                        onPressed: () => showAiPracticeGenerateSheet(context),
                        trailingIcon: Icons.add_rounded,
                      )
                    : SessionPrimaryAction(
                        label: AppStrings.aiHubConnectCta,
                        onPressed: () => context.router.push(
                          const AiApiConfigRoute(),
                        ),
                        trailingIcon: Icons.arrow_forward_rounded,
                      ),
              ),
          ],
        ),
      ),
    );
  }

  /// 区块标题 + 目录行（发丝线分隔），一组。
  List<Widget> _group(
    BuildContext context, {
    required String title,
    required List<AiCourse> items,
    String? footnote,
  }) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageMargin,
          0,
          AppSpacing.pageMargin,
          AppSpacing.xs + 2,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.sectionTitle(context),
              ),
            ),
            Text(
              AppStrings.aiPracticeGroupCount(items.length),
              style: AppTextStyles.captionSm(context).copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: TurnaTheme.textHintColor(context),
              ),
            ),
          ],
        ),
      ),
      if (footnote != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            0,
            AppSpacing.pageMargin,
            AppSpacing.sm,
          ),
          child: Text(
            footnote,
            style: AppTextStyles.captionSm(context).copyWith(
              color: TurnaTheme.textHintColor(context),
              height: 1.4,
            ),
          ),
        ),
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageMargin,
          ),
          child: AiPracticeCard(
            item: items[i],
            selectionMode: _selectionMode,
            selected: _selected.contains(items[i].id),
            showDivider: i < items.length - 1,
            onTap: () => _toggle(items[i]),
            onStart: () => openAiPractice(context, items[i]),
            onPin: () => togglePin(context, items[i], pinned: true),
            onUnpin: () => togglePin(context, items[i], pinned: false),
            onAdjust: () => adjustAiPractice(context, items[i]),
            onDetail: () => context.router.push(
              AiPracticeDetailRoute(courseId: items[i].id),
            ),
            onDelete: () => deleteAiPractices(context, [items[i]]),
            onRetry: () => retryAiPractice(context, items[i]),
            onCancel: () => cancelAiPractice(context, items[i]),
          ),
        ),
    ];
  }

  /// 空态：一行引导文案（未配置时改说连接），不铺空卡。
  Widget _empty(BuildContext context, bool complete) {
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageMargin,
        vertical: AppSpacing.xxxl,
      ),
      children: [
        Icon(
          Icons.auto_awesome_rounded,
          size: 44,
          color: TurnaTheme.brandTeal.withValues(alpha: 0.6),
        ),
        const SizedBox(height: AppSpacing.md + 2),
        Text(
          complete
              ? AppStrings.aiPracticeSectionEmpty
              : AppStrings.aiPracticeLibraryNotConfiguredHint,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyText(context).copyWith(
            color: TurnaTheme.textSecondaryColor(context),
            fontSize: 15,
            height: 1.5,
          ),
        ),
        if (complete) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppStrings.aiPracticeExpiryHint,
            textAlign: TextAlign.center,
            style: AppTextStyles.captionSm(context).copyWith(
              color: TurnaTheme.textHintColor(context),
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _selectionBar(BuildContext context, List<AiCourse> items) {
    final selectedItems =
        items.where((item) => _selected.contains(item.id)).toList();
    final allSelected = selectedItems.length == items.length;
    return SessionActionBand(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: () => setState(() {
              if (allSelected) {
                _selected.clear();
              } else {
                _selected.addAll(items.map((item) => item.id));
              }
            }),
            child: Text(
              allSelected
                  ? AppStrings.aiPracticeSelect
                  : AppStrings.aiPracticeSelectAll,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: selectedItems.isEmpty
                ? null
                : () => _pinSelected(selectedItems),
            icon: const Icon(Icons.star_border_rounded, size: 18),
            label: Text(AppStrings.aiPracticeFavorite),
          ),
          const SizedBox(width: AppSpacing.xs),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: TurnaTheme.error,
            ),
            onPressed: selectedItems.isEmpty
                ? null
                : () => _deleteSelected(selectedItems),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(AppStrings.aiPracticeDelete),
          ),
        ],
      ),
    );
  }

  void _toggle(AiCourse item) {
    setState(() {
      if (!_selectionMode) {
        _selectionMode = true;
      }
      if (!_selected.remove(item.id)) _selected.add(item.id);
    });
  }

  Future<void> _deleteSelected(List<AiCourse> items) async {
    await deleteAiPractices(context, items);
    if (!mounted) return;
    setState(() {
      _selected.clear();
      if (context.read<AiPracticeJobQueue>().items.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  Future<void> _pinSelected(List<AiCourse> items) async {
    final allPinned = items.every((item) => item.pinned);
    await context
        .read<AiPracticeJobQueue>()
        .setPinned(items.map((item) => item.id), pinned: !allPinned);
    if (!mounted) return;
    TurnaSnackBar.show(
      context,
      allPinned
          ? AppStrings.aiPracticeUnfavoritedToast
          : AppStrings.aiPracticeFavoritedToast,
    );
  }
}
