// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/views/anki_official/official_anki_canonical_card_view.dart';
import 'package:turna/views/lesson/components/cached_asset_image.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/lesson_practice_card.dart';
import 'package:turna/core/theme.dart';

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
    if (OfficialAnkiCourseEntry.parseCanonicalLink(i.context) != null) {
      return OfficialAnkiCanonicalCardView(
        contextToken: i.context!,
        submitted: state.submitted,
        onSubmit: (correct) => onSubmit(correct),
      );
    }
    final hasInline = i.term != null && i.term!.isNotEmpty;
    final isUnknown =
        !hasInline && i.wordId.startsWith(unknownInteractionWordIdPrefix);
    final vocab = (hasInline || isUnknown) ? null : vocabById[i.wordId];
    final term =
        hasInline ? i.term! : (vocab?.term ?? (isUnknown ? '' : i.wordId));
    final translation =
        hasInline ? (i.translation ?? '') : (vocab?.translation ?? '');
    final contextSentence = i.example ?? i.context;

    return _ShowWordCard(
      wordId: i.wordId,
      term: term,
      translation: translation,
      contextSentence: contextSentence,
      imageAsset: i.imageAsset,
      speakVocab: !hasInline && !isUnknown,
      audioController: _audioController,
      submitted: state.submitted,
      onTap: () => onSubmit(true),
      isUnknown: isUnknown,
    );
  }
}

class _ShowWordCard extends StatefulWidget {
  final String wordId;
  final String term;
  final String translation;
  final String? contextSentence;
  final String? imageAsset;
  final bool speakVocab;
  final AudioController audioController;
  final VoidCallback onTap;
  final bool submitted;
  final bool isUnknown;

  const _ShowWordCard({
    required this.wordId,
    required this.term,
    required this.translation,
    required this.contextSentence,
    required this.imageAsset,
    required this.speakVocab,
    required this.audioController,
    required this.onTap,
    required this.submitted,
    this.isUnknown = false,
  });

  @override
  State<_ShowWordCard> createState() => _ShowWordCardState();
}

class _ShowWordCardState extends State<_ShowWordCard> {
  DateTime? _lastSubmitAt;

  void _handleTap() {
    if (widget.submitted) return;
    final now = DateTime.now();
    if (_lastSubmitAt != null &&
        now.difference(_lastSubmitAt!) < const Duration(milliseconds: 300)) {
      return;
    }
    _lastSubmitAt = now;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isUnknown) {
      // Load-time parse failure (see Interaction.fromJson) — render a benign
      // placeholder instead of the diagnostic sentinel as a giant vocab card.
      return _UnknownItemCard(onTap: _handleTap);
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
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            onTap: widget.submitted ? null : _handleTap,
            child: LessonPracticeCard(
              variant: LessonPracticeCardVariant.surface,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Tappable word: speak the term, don't advance. Its own
                  // Semantics makes it a distinct, labeled button so screen
                  // readers can reach the pronunciation action independently
                  // of the card's "continue" tap.
                  Semantics(
                    button: true,
                    label: AppStrings.lessonSpeakTerm(widget.term),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.speakVocab
                          ? widget.audioController.speakWord(widget.wordId)
                          : widget.audioController.speak(widget.term),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.term,
                              style: TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w700,
                                color: TurnaTheme.textPrimaryColor(context),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.volume_up_rounded,
                              color: TurnaTheme.brandTeal,
                              size: 28,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (widget.imageAsset != null &&
                      widget.imageAsset!.isNotEmpty) ...[
                    RoundedCachedAssetImage(asset: widget.imageAsset!),
                    const SizedBox(height: 12),
                  ],
                  if (widget.translation.isNotEmpty)
                    Text(
                      widget.translation,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        color: TurnaTheme.textSecondaryColor(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (widget.contextSentence != null &&
                      widget.contextSentence!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Semantics(
                      button: true,
                      label: AppStrings.lessonSpeakContextSentence,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.audioController.speak(
                          _targetPart(widget.contextSentence!),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: TurnaTheme.brandTeal.withValues(alpha: 0.06),
                            borderRadius:
                                BorderRadius.circular(TurnaTheme.radiusMedium),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.volume_up_rounded,
                                color: TurnaTheme.brandTeal,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  widget.contextSentence!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color:
                                        TurnaTheme.textSecondaryColor(context),
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
                    AppStrings.lessonTapToContinue,
                    style: TextStyle(
                      fontSize: 13,
                      color: TurnaTheme.textHintColor(context)
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
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            onTap: onTap,
            child: LessonPracticeCard(
              variant: LessonPracticeCardVariant.surface,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.help_outline_rounded,
                    size: 48,
                    color: TurnaTheme.textHint.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppStrings.lessonItemNotLoaded,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: TurnaTheme.textHintColor(context),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    AppStrings.lessonTapToContinue,
                    style: TextStyle(
                      fontSize: 13,
                      color: TurnaTheme.textHintColor(context)
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
