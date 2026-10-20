// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/practice/ai_practice_job_queue.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/ai/components/ai_practice_actions.dart';
import 'package:turna/views/ai/components/ai_practice_card.dart';
import 'package:turna/views/ai/components/ai_practice_generate_sheet.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// Full AI course library, grouped the way the content actually behaves:
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

    return Scaffold(
      backgroundColor: TurnaTheme.surfaceColor(context),
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          AppStrings.aiPracticeSectionTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
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
                    ? _empty(context)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        children: [
                          if (favorites.isNotEmpty)
                            ..._group(
                              context,
                              title: AppStrings.aiPracticeGroupFavorites,
                              items: favorites,
                              accent: TurnaTheme.anatolianClay,
                            ),
                          if (drafts.isNotEmpty) ...[
                            if (favorites.isNotEmpty)
                              const SizedBox(height: 20),
                            ..._group(
                              context,
                              title: AppStrings.aiPracticeGroupDrafts,
                              items: drafts,
                              accent: TurnaTheme.brandTeal,
                              footnote: AppStrings.aiPracticeExpiryHint,
                            ),
                          ],
                          if (tasks.isNotEmpty) ...[
                            if (favorites.isNotEmpty || drafts.isNotEmpty)
                              const SizedBox(height: 20),
                            ..._group(
                              context,
                              title: AppStrings.aiPracticeGroupTasks,
                              items: tasks,
                              accent: TurnaTheme.warning,
                            ),
                          ],
                        ],
                      ),
              ),
            ),
            if (_selectionMode && items.isNotEmpty)
              _selectionBar(context, items),
            if (!_selectionMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => showAiPracticeGenerateSheet(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(AppStrings.aiPracticeGenerateTitle),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Header + cards for one group.
  List<Widget> _group(
    BuildContext context, {
    required String title,
    required List<AiCourse> items,
    required Color accent,
    String? footnote,
  }) {
    return [
      Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: TurnaTheme.textPrimaryColor(context),
                ),
          ),
          const SizedBox(width: 6),
          Text(
            AppStrings.aiPracticeGroupCount(items.length),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textSecondaryColor(context),
                ),
          ),
        ],
      ),
      if (footnote != null) ...[
        const SizedBox(height: 4),
        Text(
          footnote,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TurnaTheme.textSecondaryColor(context),
                height: 1.4,
              ),
        ),
      ],
      const SizedBox(height: 10),
      for (var i = 0; i < items.length; i++) ...[
        AiPracticeCard(
          item: items[i],
          selectionMode: _selectionMode,
          selected: _selected.contains(items[i].id),
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
        if (i < items.length - 1) const SizedBox(height: 10),
      ],
    ];
  }

  Widget _empty(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(
          Icons.auto_awesome_rounded,
          size: 44,
          color: TurnaTheme.brandTeal.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 14),
        Text(
          AppStrings.aiPracticeSectionEmpty,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: TurnaTheme.textSecondaryColor(context),
                height: 1.5,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.aiPracticeExpiryHint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TurnaTheme.textSecondaryColor(context),
                height: 1.5,
              ),
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            onPressed: () => showAiPracticeGenerateSheet(context),
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(AppStrings.aiPracticeGenerateTitle),
          ),
        ),
      ],
    );
  }

  Widget _selectionBar(BuildContext context, List<AiCourse> items) {
    final selectedItems =
        items.where((item) => _selected.contains(item.id)).toList();
    final allSelected = selectedItems.length == items.length;
    return Material(
      color: TurnaTheme.cardBg(context),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
              const SizedBox(width: 4),
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
        ),
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
