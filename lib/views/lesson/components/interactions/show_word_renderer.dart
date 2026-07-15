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
    final isUnknown = i.wordId.startsWith(unknownInteractionWordIdPrefix);
    final vocab = isUnknown ? null : vocabById[i.wordId];
    final term = vocab?.term ?? (isUnknown ? '' : i.wordId);
    final translation = vocab?.translation ?? '';

    return _ShowWordCard(
      term: term,
      translation: translation,
      contextSentence: i.context,
      audioController: _audioController,
      onTap: () => onSubmit(true),
      // A sentinel ShowWord is a load-time parse failure (see
      // Interaction.fromJson), not a real vocab card. Don't expose the
      // speak/pronounce affordances on it — there's no term to speak, and
      // surfacing the diagnostic wordId to TTS would read the sentinel aloud.
      isUnknown: isUnknown,
    );
  }
}

class _ShowWordCard extends StatelessWidget {
  final String term;
  final String translation;
  final String? contextSentence;
  final AudioController audioController;
  final VoidCallback onTap;
  final bool isUnknown;

  const _ShowWordCard({
    required this.term,
    required this.translation,
    required this.contextSentence,
    required this.audioController,
    required this.onTap,
    this.isUnknown = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isUnknown) {
      // Load-time parse failure (see Interaction.fromJson) — render a benign
      // placeholder instead of the diagnostic sentinel as a giant vocab card.
      return _UnknownItemCard(onTap: onTap);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        // The card itself is the tappable "continue" affordance. We do NOT
        // wrap it in a button-labeled Semantics: that would merge the whole
        // subtree into one node and swallow the inner tap-to-speak gestures,
        // making pronunciation inaccessible to screen readers. The InkWell
        // already exposes a tap action; the speak buttons below carry their
        // own Semantics so they surface as distinct, labeled actions.
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
                  // Tappable word: speak the term, don't advance. Its own
                  // Semantics makes it a distinct, labeled button so screen
                  // readers can reach the pronunciation action independently
                  // of the card's "continue" tap.
                  Semantics(
                    button: true,
                    label: 'Speak $term',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
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
                    Semantics(
                      button: true,
                      label: 'Speak context sentence',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
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

/// Rendered in place of a [ShowWord] whose `wordId` is an
/// `unknown-interaction:` sentinel — a load-time parse failure surfaced by
/// [Interaction.fromJson]. Acknowledging the card advances the lesson so the
/// user is not stuck; the bad item is otherwise blank, never showing the
/// diagnostic string as a word.
class _UnknownItemCard extends StatelessWidget {
  final VoidCallback onTap;

  const _UnknownItemCard({required this.onTap});

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
                  Icon(
                    Icons.help_outline_rounded,
                    size: 48,
                    color: VarnamalaTheme.textHint.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This item could not be loaded.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: VarnamalaTheme.textHintColor(context),
                    ),
                  ),
                  const SizedBox(height: 24),
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
}
