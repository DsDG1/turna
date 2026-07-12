// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/courses/languages/vocab.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/theme.dart';

/// Flashcard introducing a vocabulary word.
///
/// No correctness check — the user just acknowledges the card. We treat every
/// acknowledgement as "correct" so the viewmodel marks the item complete and
/// auto-advances.
@injectable
class ShowWordRenderer extends InteractionRenderer {
  final AudioController _audioController;

  ShowWordRenderer(this._audioController);

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
    final vocab = vocabById[i.wordId];
    final term = vocab?.term ?? i.wordId;
    final translation = vocab?.translation ?? '';

    return _ShowWordCard(
      term: term,
      translation: translation,
      contextSentence: i.context,
      audioController: _audioController,
      onTap: () => onSubmit(true),
    );
  }
}

class _ShowWordCard extends StatelessWidget {
  final String term;
  final String translation;
  final String? contextSentence;
  final AudioController audioController;
  final VoidCallback onTap;

  const _ShowWordCard({
    required this.term,
    required this.translation,
    required this.contextSentence,
    required this.audioController,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Material(
          color: VarnamalaTheme.cardBg(context),
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
                  // Tappable word: speak the term, don't advance.
                  GestureDetector(
                    onTap: () => audioController.speak(term),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          term,
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            color: VarnamalaTheme.textPrimaryColor(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.volume_up_rounded,
                          color: VarnamalaTheme.peacockTeal,
                          size: 28,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (translation.isNotEmpty)
                    Text(
                      translation,
                      style: TextStyle(
                        fontSize: 20,
                        color: VarnamalaTheme.textSecondaryColor(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (contextSentence != null && contextSentence!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () => audioController.speak(
                        _targetPart(contextSentence!),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: VarnamalaTheme.peacockTeal
                              .withValues(alpha: 0.06),
                          borderRadius:
                              BorderRadius.circular(VarnamalaTheme.radiusMedium),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.volume_up_rounded,
                              color: VarnamalaTheme.peacockTeal,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                contextSentence!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: VarnamalaTheme.textSecondaryColor(
                                      context),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Text(
                    'Tap to continue',
                    style: TextStyle(
                      fontSize: 13,
                      color: VarnamalaTheme.textHintColor(context)
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

  /// If the context sentence includes a translation separator, speak only the
  /// first (target-language) part; otherwise speak the whole sentence.
  static String _targetPart(String sentence) {
    final match = RegExp(r'\s*[—–-]\s*|\s*\|\s*').firstMatch(sentence);
    if (match != null) {
      return sentence.substring(0, match.start).trim();
    }
    return sentence.trim();
  }
}
