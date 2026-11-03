// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/courses/languages/grammar_points.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/motion.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/directory_rows.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';
import 'package:turna/views/widgets/turna_select.dart';

/// List filter: everything, word mistakes only, or grammar mistakes only.
enum _MistakeFilter { all, words, grammar }

/// 我的错题 ——「湿地雾光」R09 学习笔记式列表。
///
/// 行不是卡：条目主体是**问题摘要**（16/600 标题 + 正确表达释义行 + 12px
/// 元信息），来源 / 时间作旁注；点行进详情页（分段对照 + 稳定「重练」）。
/// 类型筛选、下拉刷新、空态保持不变。
@RoutePage()
class MistakeListPage extends StatefulWidget {
  const MistakeListPage({super.key});

  @override
  State<MistakeListPage> createState() => _MistakeListPageState();
}

class _MistakeListPageState extends State<MistakeListPage> {
  _MistakeFilter _filter = _MistakeFilter.all;

  @override
  Widget build(BuildContext context) {
    final mistakes = context.select((MistakeProvider p) => p.entries);
    final wordCount = mistakes.where((e) => e.wordId != null).length;
    final grammarCount = mistakes.where((e) => e.grammarPointId != null).length;
    final visible = switch (_filter) {
      _MistakeFilter.all => mistakes,
      _MistakeFilter.words =>
        mistakes.where((e) => e.wordId != null).toList(growable: false),
      _MistakeFilter.grammar =>
        mistakes.where((e) => e.grammarPointId != null).toList(growable: false),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.reviewMyMistakesTitle),
        actions: [
          IconButton(
            tooltip: AppStrings.mistakeDashboardTitle,
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => context.router.push(const MistakeDashboardRoute()),
          ),
        ],
      ),
      body: mistakes.isEmpty
          ? PracticeEmptyState(
              title: AppStrings.reviewNoMistakesRecorded,
              message: AppStrings.reviewKeepItUp,
            )
          : RefreshIndicator(
              color: TurnaTheme.brandTeal,
              onRefresh: () =>
                  context.read<MistakeProvider>().reloadFromPrefs(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageMargin,
                        AppSpacing.md,
                        AppSpacing.pageMargin,
                        0,
                      ),
                      child: _FilterBar(
                        selected: _filter,
                        allCount: mistakes.length,
                        wordCount: wordCount,
                        grammarCount: grammarCount,
                        onSelected: (filter) =>
                            setState(() => _filter = filter),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.pageMargin,
                      vertical: AppSpacing.sm,
                    ),
                    sliver: SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) => _RevealOnMount(
                        index: index,
                        child: _MistakeEntryRow(mistake: visible[index]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// 类型筛选行：全部 / 单词 / 语法，label 带当前计数。
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.allCount,
    required this.wordCount,
    required this.grammarCount,
    required this.onSelected,
  });

  final _MistakeFilter selected;
  final int allCount;
  final int wordCount;
  final int grammarCount;
  final ValueChanged<_MistakeFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        TurnaFilterChip(
          label: '${AppStrings.reviewMistakeFilterAll} $allCount',
          selected: selected == _MistakeFilter.all,
          onSelected: (_) => onSelected(_MistakeFilter.all),
        ),
        TurnaFilterChip(
          label: '${AppStrings.reviewWordsLabel} $wordCount',
          selected: selected == _MistakeFilter.words,
          onSelected: (_) => onSelected(_MistakeFilter.words),
        ),
        TurnaFilterChip(
          label: '${AppStrings.reviewGrammarLabel} $grammarCount',
          selected: selected == _MistakeFilter.grammar,
          onSelected: (_) => onSelected(_MistakeFilter.grammar),
        ),
      ],
    );
  }
}

/// 卡片交错入场：淡入 + 12px 上浮，节奏由 [TurnaMotion.stagger] 决定；
/// reduceMotion（MediaQuery.disableAnimations，根注入已合并系统与设置）
/// 时时长归零、立即呈现。
class _RevealOnMount extends StatelessWidget {
  const _RevealOnMount({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: TurnaMotion.scaled(TurnaMotion.smooth, reduceMotion),
      curve: TurnaMotion.stagger(index),
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// 学习笔记式条目：问题摘要 + 正确表达释义行 + 来源 / 时间旁注；
/// 重写进度点放行尾（带 Semantics 文本，不只靠颜色表达）。
class _MistakeEntryRow extends StatelessWidget {
  const _MistakeEntryRow({required this.mistake});

  final MistakeEntry mistake;

  @override
  Widget build(BuildContext context) {
    final word = mistake.wordId != null ? vocabById[mistake.wordId!] : null;
    final grammar = mistake.grammarPointId != null
        ? grammarPointById[mistake.grammarPointId!]
        : null;
    final title = word?.term ??
        grammar?.title ??
        (mistake.interactionId.isNotEmpty
            ? mistake.interactionId
            : AppStrings.reviewUnknownQuestion);
    final correct = word?.translation ?? mistake.correctAnswer;
    final typeLabel = grammar != null
        ? AppStrings.reviewGrammarLabel
        : word != null
            ? AppStrings.reviewWordsLabel
            : AppStrings.mistakeDashboardOtherType;

    return DirectoryEntryRow(
      title: title,
      subtitle: correct.isEmpty ? null : correct,
      meta: '$typeLabel · ${AppStrings.timeAgo(mistake.timestamp)}',
      trailing: Semantics(
        label: AppStrings.reviewRewriteProgress(
          mistake.rewriteCount,
          MistakeProvider.rewriteGoal,
        ),
        child: _RewriteDots(count: mistake.rewriteCount),
      ),
      onTap: () =>
          context.router.push(MistakeDetailRoute(entry: mistake)),
    );
  }
}

class _RewriteDots extends StatelessWidget {
  const _RewriteDots({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < MistakeProvider.rewriteGoal; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < count
                  ? TurnaTheme.brandTeal
                  : TurnaTheme.dividerBg(context),
            ),
          ),
        ],
      ],
    );
  }
}
