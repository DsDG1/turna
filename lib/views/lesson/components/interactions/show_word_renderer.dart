// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/courses/languages/kannada_vocab.dart';
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:words625/views/theme.dart';

/// Flashcard introducing a vocabulary word.
///
/// No correctness check — the user just acknowledges the card. We treat every
/// acknowledgement as "correct" so the viewmodel marks the item complete and
/// auto-advances.
@injectable
class ShowWordRenderer extends InteractionRenderer {
  @override
  Type get handlesType => ShowWord;

  /// ShowWord has no correctness check — it auto-advances on card tap, so
  /// the lesson screen must not render a Continue button for it.
  @override
  bool get autoAdvance => true;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as ShowWord;
    final vocab = swahiliVocabById[i.wordId];
    final term = vocab?.term ?? i.wordId;
    final translation = vocab?.translation ?? '';

    return _ShowWordCard(
      term: term,
      translation: translation,
      contextSentence: i.context,
      onTap: () => onSubmit(true),
    );
  }
}

class _ShowWordCard extends StatelessWidget {
  final String term;
  final String translation;
  final String? contextSentence;
  final VoidCallback onTap;

  const _ShowWordCard({
    required this.term,
    required this.translation,
    required this.contextSentence,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Material(
          color: Colors.white,
          elevation: 2,
          shadowColor: VarnamalaTheme.peacockTeal.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
          child: InkWell(
            borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    term,
                    style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      color: VarnamalaTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (translation.isNotEmpty)
                    Text(
                      translation,
                      style: const TextStyle(
                        fontSize: 20,
                        color: VarnamalaTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (contextSentence != null && contextSentence!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: VarnamalaTheme.peacockTeal
                            .withValues(alpha: 0.06),
                        borderRadius:
                            BorderRadius.circular(VarnamalaTheme.radiusMedium),
                      ),
                      child: Text(
                        contextSentence!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          color: VarnamalaTheme.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Text(
                    'Tap to continue',
                    style: TextStyle(
                      fontSize: 13,
                      color: VarnamalaTheme.textHint
                          .withValues(alpha: 0.8),
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
