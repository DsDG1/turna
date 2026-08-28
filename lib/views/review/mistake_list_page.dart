// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_hint_provider.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/courses/languages/dictionary.dart';
import 'package:turna/courses/languages/grammar_points.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/ai/components/ai_not_configured_panel.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';

@RoutePage()
class MistakeListPage extends StatelessWidget {
  const MistakeListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mistakes = context.select((MistakeProvider p) => p.entries);

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.reviewMyMistakesTitle)),
      body: mistakes.isEmpty
          ? PracticeEmptyState(
              title: AppStrings.reviewNoMistakesRecorded,
              message: AppStrings.reviewKeepItUp,
            )
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

void _openWhyWrong(
  BuildContext context, {
  required MistakeEntry mistake,
  required String displayQuestion,
  required String correctAnswer,
}) {
  final config = context.read<AiEngineConfigHolder>().config;
  if (!config.isComplete) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SafeArea(
        child: AiNotConfiguredPanel(compact: true),
      ),
    );
    return;
  }
  final qctx = AiQuestionContext(
    language: 'Turkish',
    typeLabel: 'Mistake',
    promptLabel: displayQuestion,
    correctLabel: correctAnswer,
    userAnswer: mistake.userAnswer,
  );
  final provider = context.read<AiHintProvider>();
  // Fire why-wrong as a depth call; surface via hint chat for streaming UX.
  provider.reset();
  context.router.push(AiHintChatRoute(context: qctx));
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
            // 原来用 Row + Spacer 把"我学会了"推到右边;3 个按钮在窄屏(尤其是
            // 出现"复习语法"条件按钮时)总宽会挤爆 Spacer。换成 Wrap 让按钮
            // 空间不够时自然换行,保留全部可点性。
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
                  icon: Icons.auto_awesome_rounded,
                  label: AppStrings.aiExplainWhyWrong,
                  onTap: () => _openWhyWrong(
                    context,
                    mistake: mistake,
                    displayQuestion: displayQuestion,
                    correctAnswer: correctAnswer,
                  ),
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
        color: TurnaTheme.tintSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: TurnaTheme.brandTeal,
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
        color: TurnaTheme.inputFillColor(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AnswerBlock(
              label: AppStrings.reviewYourAnswer,
              value: userAnswer.isEmpty ? AppStrings.reviewDash : userAnswer,
              valueColor: TurnaTheme.error,
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
