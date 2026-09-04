// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/courses/languages/dictionary.dart';
import 'package:turna/courses/languages/grammar_points.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/home/motion/turna_motion.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';
import 'package:turna/views/widgets/turna_select.dart';

/// List filter: everything, word mistakes only, or grammar mistakes only.
enum _MistakeFilter { all, words, grammar }

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
      _MistakeFilter.words => mistakes
          .where((e) => e.wordId != null)
          .toList(growable: false),
      _MistakeFilter.grammar => mistakes
          .where((e) => e.grammarPointId != null)
          .toList(growable: false),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.reviewMyMistakesTitle),
        actions: [
          IconButton(
            tooltip: AppStrings.mistakeDashboardTitle,
            icon: const Icon(Icons.insights_outlined),
            onPressed: () =>
                context.router.push(const MistakeDashboardRoute()),
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
              onRefresh: () async {
                // 重新从 prefs 解码（外部恢复/清理后同步），spinner 稍作停留。
                context.read<MistakeProvider>().reloadFromPrefs();
                await Future<void>.delayed(
                  const Duration(milliseconds: 400),
                );
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _MistakesStatsHeader(mistakes: mistakes),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _FilterBar(
                        selected: _filter,
                        allCount: mistakes.length,
                        wordCount: wordCount,
                        grammarCount: grammarCount,
                        onSelected: (filter) => setState(() => _filter = filter),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _RevealOnMount(
                        index: index,
                        child: _MistakeCard(mistake: visible[index]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MistakesStatsHeader extends StatelessWidget {
  final List<MistakeEntry> mistakes;

  const _MistakesStatsHeader({required this.mistakes});

  @override
  Widget build(BuildContext context) {
    final wordCount = mistakes.where((e) => e.wordId != null).length;
    final grammarCount = mistakes.where((e) => e.grammarPointId != null).length;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Flexible 防止多语言长 label(德语 / 俄语 / 土耳其语)在窄屏上把整行挤爆
          Flexible(
            child: _StatItem(
              icon: Icons.error_outline_rounded,
              iconColor: TurnaTheme.error,
              value: mistakes.length.toString(),
              label: AppStrings.reviewMistakesLabel,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: TurnaTheme.dividerBg(context),
          ),
          Flexible(
            child: _StatItem(
              icon: Icons.translate_rounded,
              iconColor: TurnaTheme.brandTeal,
              value: wordCount.toString(),
              label: AppStrings.reviewWordsLabel,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: TurnaTheme.dividerBg(context),
          ),
          Flexible(
            child: _StatItem(
              icon: Icons.school_rounded,
              iconColor: TurnaTheme.leagueAmethyst,
              value: grammarCount.toString(),
              label: AppStrings.reviewGrammarLabel,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatItem({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TurnaTheme.textHintColor(context),
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
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

class _MistakeCard extends StatelessWidget {
  final MistakeEntry mistake;

  const _MistakeCard({required this.mistake});

  @override
  Widget build(BuildContext context) {
    final word = mistake.wordId != null ? vocabById[mistake.wordId!] : null;
    final grammar = mistake.grammarPointId != null
        ? grammarPointById[mistake.grammarPointId!]
        : null;
    final displayQuestion = word?.term ??
        (mistake.interactionId.isNotEmpty
            ? mistake.interactionId
            : AppStrings.reviewUnknownQuestion);
    final correctAnswer = word?.translation ?? mistake.correctAnswer;
    final resolvedMeaning = word == null && correctAnswer.isNotEmpty
        ? getWordMeaning(correctAnswer)
        : '--';
    final showMeaning =
        resolvedMeaning != '--' && resolvedMeaning != correctAnswer;

    final isGrammar = mistake.grammarPointId != null;
    final isWord = mistake.wordId != null;

    return Container(
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TypeIcon(isWord: isWord, isGrammar: isGrammar),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayQuestion,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      if (grammar != null) ...[
                        const SizedBox(height: 6),
                        _GrammarChip(title: grammar.title),
                      ],
                      const SizedBox(height: 6),
                      _MetaRow(mistake: mistake),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _PracticeButton(mistake: mistake),
              ],
            ),
            const SizedBox(height: 16),
            _AnswerComparison(
              userAnswer: mistake.userAnswer,
              correctAnswer: correctAnswer,
            ),
            if (showMeaning) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 14,
                    color: TurnaTheme.textHintColor(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      resolvedMeaning,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textSecondaryColor(context),
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            // 条件按钮"复习语法"出现时,窄屏 + 多语言长 label 仍可能挤爆
            // 一行;Wrap 保证空间不足时自然换行,保留全部可点性。
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.start,
              children: [
                if (mistake.grammarPointId != null)
                  _TextActionButton(
                    icon: Icons.menu_book_rounded,
                    label: AppStrings.reviewReviewGrammar,
                    onTap: () async {
                      await context
                          .read<GrammarReviewProvider>()
                          .markDueNow(mistake.grammarPointId!);
                      if (context.mounted) {
                        context.router.push(const GrammarReviewRoute());
                      }
                    },
                  ),
                _TextActionButton(
                  icon: Icons.check_circle_outline_rounded,
                  label: AppStrings.reviewGotItNow,
                  onTap: () =>
                      context.read<MistakeProvider>().recordRewrite(mistake.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 小字元信息行：相对时间 + 重写进度点（答对 [MistakeProvider.rewriteGoal]
/// 次后条目自动移除；进度点同时带 Semantics 文本，不只靠颜色表达）。
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.mistake});

  final MistakeEntry mistake;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.schedule_rounded,
          size: 12,
          color: TurnaTheme.textHintColor(context),
        ),
        const SizedBox(width: 4),
        Text(
          AppStrings.timeAgo(mistake.timestamp),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: TurnaTheme.textHintColor(context),
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(width: 10),
        Semantics(
          label: AppStrings.reviewRewriteProgress(
            mistake.rewriteCount,
            MistakeProvider.rewriteGoal,
          ),
          child: _RewriteDots(count: mistake.rewriteCount),
        ),
      ],
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

/// 类型图标按错题种类着色：单词=品牌青、语法=紫晶、其他=中性，让两类
/// 错题在列表里一眼可分。
class _TypeIcon extends StatelessWidget {
  final bool isWord;
  final bool isGrammar;

  const _TypeIcon({
    required this.isWord,
    required this.isGrammar,
  });

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color foreground;
    final Color background;
    if (isGrammar) {
      icon = Icons.school_rounded;
      foreground = TurnaTheme.leagueAmethyst;
      background = TurnaTheme.leagueAmethyst.withValues(alpha: 0.12);
    } else if (isWord) {
      icon = Icons.translate_rounded;
      foreground = TurnaTheme.brandTeal;
      background = TurnaTheme.tintSoft;
    } else {
      icon = Icons.help_outline_rounded;
      foreground = TurnaTheme.textSecondaryColor(context);
      background = TurnaTheme.inputFillColor(context);
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: foreground,
        size: 22,
      ),
    );
  }
}

class _GrammarChip extends StatelessWidget {
  final String title;

  const _GrammarChip({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        AppStrings.reviewGrammarChip(title),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: TurnaTheme.brandTeal,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _PracticeButton extends StatelessWidget {
  final MistakeEntry mistake;

  const _PracticeButton({required this.mistake});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => context.router.push(
        MistakePracticeRoute(entry: mistake),
      ),
      icon: const Icon(Icons.play_arrow_rounded, size: 18),
      label: Text(AppStrings.commonPractice),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 你的答案 vs 正确答案：两个色块各带浅色底（错误=红 8%、正确=青 8%），
/// 文字保持红/绿语义色，中间箭头提示"改错方向"。
class _AnswerComparison extends StatelessWidget {
  final String userAnswer;
  final String correctAnswer;

  const _AnswerComparison({
    required this.userAnswer,
    required this.correctAnswer,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _AnswerBlock(
            label: AppStrings.reviewYourAnswer,
            value: userAnswer.isEmpty ? AppStrings.reviewDash : userAnswer,
            valueColor: TurnaTheme.error,
            blockColor: TurnaTheme.error.withValues(alpha: 0.08),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            Icons.arrow_forward_rounded,
            size: 16,
            color: TurnaTheme.textHint,
          ),
        ),
        Expanded(
          child: _AnswerBlock(
            label: AppStrings.reviewCorrectAnswer,
            value:
                correctAnswer.isEmpty ? AppStrings.reviewDash : correctAnswer,
            valueColor: TurnaTheme.brandTeal,
            blockColor: TurnaTheme.brandTeal.withValues(alpha: 0.08),
          ),
        ),
      ],
    );
  }
}

class _AnswerBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final Color blockColor;

  const _AnswerBlock({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.blockColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: blockColor,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHint,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: valueColor,
                  fontWeight: FontWeight.w700,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TextActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TextActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
