// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:words625/application/grammar_review_provider.dart';
import 'package:words625/application/mistake_provider.dart';
import 'package:words625/courses/languages/grammar_points.dart';
import 'package:words625/courses/languages/swahili_vocab.dart';
import 'package:words625/routing/routing.gr.dart';
import 'package:words625/views/theme.dart';

@RoutePage()
class MistakeListPage extends StatelessWidget {
  const MistakeListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mistakes = context.watch<MistakeProvider>().entries;

    return Scaffold(
      appBar: AppBar(title: const Text('My Mistakes')),
      body: mistakes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 64,
                    color: VarnamalaTheme.success,
                  ),
                  const SizedBox(height: 16),
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
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: mistakes.length,
              itemBuilder: (context, index) {
                final mistake = mistakes[index];
                final word = mistake.wordId != null
                    ? swahiliVocabById[mistake.wordId!]
                    : null;
                final grammar = mistake.grammarPointId != null
                    ? swahiliGrammarPointById[mistake.grammarPointId!]
                    : null;
                final displayQuestion = word?.term ??
                    (mistake.interactionId.isNotEmpty
                        ? mistake.interactionId
                        : 'Unknown question');

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(VarnamalaTheme.radiusMedium),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
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
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: VarnamalaTheme.peacockTeal
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Grammar: ${grammar.title}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: VarnamalaTheme.peacockTeal,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        _Row(label: 'Your answer:', value: mistake.userAnswer),
                        _Row(
                            label: 'Correct answer:',
                            value: word?.translation ?? mistake.correctAnswer),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () => context
                                  .read<MistakeProvider>()
                                  .recordRewrite(mistake.id),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('I got it now'),
                            ),
                            if (mistake.grammarPointId != null)
                              TextButton.icon(
                                onPressed: () async {
                                  await context
                                      .read<GrammarReviewProvider>()
                                      .markDueNow(mistake.grammarPointId!);
                                  if (context.mounted) {
                                    context.router
                                        .push(const GrammarReviewRoute());
                                  }
                                },
                                icon: const Icon(Icons.menu_book_rounded),
                                label: const Text('Review grammar'),
                              ),
                            ElevatedButton.icon(
                              onPressed: () => context.router.push(
                                MistakePracticeRoute(entry: mistake),
                              ),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Practice'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value.isEmpty ? '—' : value,
              style: const TextStyle(color: VarnamalaTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
