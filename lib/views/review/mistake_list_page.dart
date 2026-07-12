// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/courses/languages/dictionary.dart';
import 'package:varnamala/courses/languages/grammar_points.dart';
import 'package:varnamala/courses/languages/vocab.dart';
import 'package:varnamala/domain/course/mistake_entry.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/views/theme.dart';

@RoutePage()
class MistakeListPage extends StatelessWidget {
  const MistakeListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mistakes = context.select((MistakeProvider p) => p.entries);

    return Scaffold(
      appBar: AppBar(title: const Text('My Mistakes')),
      body: mistakes.isEmpty
          ? const _EmptyState()
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _MistakesStatsHeader(mistakes: mistakes),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList.separated(
                    itemCount: mistakes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _MistakeCard(mistake: mistakes[index]);
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 72,
            color: VarnamalaTheme.success,
          ),
          const SizedBox(height: 20),
          Text(
            'No mistakes recorded',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Keep it up!',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: VarnamalaTheme.textSecondary,
                ),
          ),
        ],
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
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            icon: Icons.error_outline_rounded,
            iconColor: VarnamalaTheme.error,
            value: mistakes.length.toString(),
            label: 'Mistakes',
          ),
          Container(
            width: 1,
            height: 40,
            color: VarnamalaTheme.dividerBg(context),
          ),
          _StatItem(
            icon: Icons.translate_rounded,
            iconColor: VarnamalaTheme.peacockTeal,
            value: wordCount.toString(),
            label: 'Words',
          ),
          Container(
            width: 1,
            height: 40,
            color: VarnamalaTheme.dividerBg(context),
          ),
          _StatItem(
            icon: Icons.school_rounded,
            iconColor: VarnamalaTheme.leagueAmethyst,
            value: grammarCount.toString(),
            label: 'Grammar',
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
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: VarnamalaTheme.textHintColor(context),
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}

class _MistakeCard extends StatelessWidget {
  final MistakeEntry mistake;

  const _MistakeCard({required this.mistake});

  @override
  Widget build(BuildContext context) {
    final word = mistake.wordId != null
        ? vocabById[mistake.wordId!]
        : null;
    final grammar = mistake.grammarPointId != null
        ? grammarPointById[mistake.grammarPointId!]
        : null;
    final displayQuestion = word?.term ??
        (mistake.interactionId.isNotEmpty
            ? mistake.interactionId
            : 'Unknown question');
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
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
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
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (grammar != null) ...[
                        const SizedBox(height: 6),
                        _GrammarChip(title: grammar.title),
                      ],
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
                    color: VarnamalaTheme.textHintColor(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      resolvedMeaning,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: VarnamalaTheme.textSecondaryColor(context),
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (mistake.grammarPointId != null)
                  _TextActionButton(
                    icon: Icons.menu_book_rounded,
                    label: 'Review grammar',
                    onTap: () async {
                      await context
                          .read<GrammarReviewProvider>()
                          .markDueNow(mistake.grammarPointId!);
                      if (context.mounted) {
                        context.router.push(const GrammarReviewRoute());
                      }
                    },
                  ),
                const Spacer(),
                _TextActionButton(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'I got it now',
                  onTap: () => context
                      .read<MistakeProvider>()
                      .recordRewrite(mistake.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
    if (isGrammar) {
      icon = Icons.school_rounded;
    } else if (isWord) {
      icon = Icons.translate_rounded;
    } else {
      icon = Icons.help_outline_rounded;
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: VarnamalaTheme.tintSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: VarnamalaTheme.peacockTeal,
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
        color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Grammar: $title',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: VarnamalaTheme.peacockTeal,
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
      label: const Text('Practice'),
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

class _AnswerComparison extends StatelessWidget {
  final String userAnswer;
  final String correctAnswer;

  const _AnswerComparison({
    required this.userAnswer,
    required this.correctAnswer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VarnamalaTheme.inputFillColor(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AnswerBlock(
              label: 'Your answer',
              value: userAnswer.isEmpty ? '—' : userAnswer,
              valueColor: VarnamalaTheme.error,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: VarnamalaTheme.textHint,
            ),
          ),
          Expanded(
            child: _AnswerBlock(
              label: 'Correct answer',
              value: correctAnswer.isEmpty ? '—' : correctAnswer,
              valueColor: VarnamalaTheme.peacockTeal,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _AnswerBlock({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: VarnamalaTheme.textHint,
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
      label: Text(label),
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
