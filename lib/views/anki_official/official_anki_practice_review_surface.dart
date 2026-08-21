import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_practice/card_classifier_models.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/anki_media_strip.dart';
import 'package:turna/views/lesson/components/interactions/anki_card_renderer.dart';
import 'package:turna/views/lesson/components/interactions/fill_blank_renderer.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/interactions/listen_and_pick_renderer.dart';
import 'package:turna/views/lesson/components/interactions/multi_select_renderer.dart';
import 'package:turna/views/lesson/components/interactions/multiple_choice_renderer.dart';
import 'package:turna/views/lesson/components/interactions/show_word_renderer.dart';
import 'package:turna/views/lesson/components/interactions/type_the_word_renderer.dart';
import 'package:turna/views/lesson/components/lesson_practice_card.dart';
import 'package:turna/views/theme.dart';

/// Pure native review surface for practice-compatible cards in official review.
/// Reuses the core [InteractionRenderer] system from Turna lessons.
class OfficialAnkiPracticeReviewSurface extends StatefulWidget {
  const OfficialAnkiPracticeReviewSurface({
    super.key,
    required this.card,
    required this.phase,
    required this.paths,
    required this.onShowAnswer,
    required this.onRate,
    this.rawQuestionHtml = '',
    this.rawAnswerHtml = '',
    this.renderers,
    this.isAnswerVisible = false,
    this.presentGeneration = 0,
    this.presentedCardId = 0,
    this.onPresented,
  });

  final OfficialReviewQueueCard card;
  final OfficialReviewPhase phase;
  final OfficialAnkiPaths paths;
  final VoidCallback onShowAnswer;
  final ValueChanged<String> onRate;
  final String rawQuestionHtml;
  final String rawAnswerHtml;
  final Set<InteractionRenderer>? renderers;
  final bool isAnswerVisible;
  final int presentGeneration;
  final int presentedCardId;
  final ValueChanged<String>? onPresented;

  @override
  State<OfficialAnkiPracticeReviewSurface> createState() =>
      _OfficialAnkiPracticeReviewSurfaceState();
}

class _OfficialAnkiPracticeReviewSurfaceState
    extends State<OfficialAnkiPracticeReviewSurface> {
  InteractionState _interactionState = InteractionState.idle;
  String? _ackedSide;
  int _ackedGeneration = 0;
  int _ackedCardId = 0;

  @override
  void initState() {
    super.initState();
    _schedulePresentAck();
  }

  @override
  void didUpdateWidget(covariant OfficialAnkiPracticeReviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.cardId != widget.card.cardId) {
      _interactionState = InteractionState.idle;
      _ackedSide = null;
      _ackedGeneration = 0;
      _ackedCardId = 0;
    }
    _schedulePresentAck();
  }

  void _schedulePresentAck() {
    final side = widget.isAnswerVisible ? 'answer' : 'question';
    final generation = widget.presentGeneration;
    final cardId = widget.presentedCardId == 0
        ? widget.card.cardId
        : widget.presentedCardId;
    if (cardId <= 0 || generation <= 0) return;
    if (_ackedSide == side &&
        _ackedGeneration == generation &&
        _ackedCardId == cardId) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentSide = widget.isAnswerVisible ? 'answer' : 'question';
      if (currentSide != side) return;
      if (widget.presentGeneration != generation) return;
      _ackedSide = side;
      _ackedGeneration = generation;
      _ackedCardId = cardId;
      widget.onPresented?.call(side);
    });
  }

  AnkiPracticeClassification _classify() {
    final rawQ = widget.rawQuestionHtml.isNotEmpty
        ? widget.rawQuestionHtml
        : 'Card ${widget.card.cardId}';
    return AnkiPracticeClassification(
      shape: AnkiPracticeShape.flip,
      confidence: 1,
      term: rawQ,
      meaning: widget.rawAnswerHtml,
    );
  }

  Interaction _toInteraction(AnkiPracticeClassification c) {
    final cardId = widget.card.cardId;
    final id = 'official-review-card-$cardId';
    final rawQ = widget.rawQuestionHtml.isNotEmpty
        ? widget.rawQuestionHtml
        : 'Card $cardId';
    final rawA = widget.rawAnswerHtml;
    final term = c.term.isNotEmpty ? c.term : rawQ;
    final meaning = c.meaning.isNotEmpty ? c.meaning : rawA;

    final audioAssets = c.audioFilename != null && c.audioFilename!.isNotEmpty
        ? [c.audioFilename!]
        : const <String>[];
    final imageAssets = c.imageFilename != null && c.imageFilename!.isNotEmpty
        ? [c.imageFilename!]
        : const <String>[];

    switch (c.shape) {
      case AnkiPracticeShape.quiz:
        if (c.correctIndices != null && c.correctIndices!.length >= 2) {
          return Interaction.multiSelect(
            id: id,
            prompt: term,
            options: c.options,
            correctIndices: c.correctIndices!,
            imageAsset: c.imageFilename,
          );
        }
        return Interaction.multipleChoice(
          id: id,
          prompt: term,
          options: c.options,
          correctIndex: c.correctIndex ?? 0,
          imageAsset: c.imageFilename,
          audioAssets: audioAssets,
        );
      case AnkiPracticeShape.cloze:
        return Interaction.fillBlank(
          id: id,
          sentence:
              c.clozeSentence?.isNotEmpty == true ? c.clozeSentence! : term,
          answer: c.clozeAnswer?.isNotEmpty == true ? c.clozeAnswer! : meaning,
          hint: c.pronunciation,
          audioAssets: audioAssets,
          imageAssets: imageAssets,
        );
      case AnkiPracticeShape.listen:
        if (audioAssets.isNotEmpty) {
          final options = c.options.isNotEmpty
              ? c.options
              : [meaning, 'Option B', 'Option C'];
          return Interaction.listenAndPick(
            id: id,
            audioAsset: audioAssets.first,
            prompt: meaning.isEmpty ? 'Listen and pick' : meaning,
            options: options,
            correctIndex: c.correctIndex ?? 0,
          );
        }
        return Interaction.ankiCard(
          id: id,
          front: term,
          back: meaning,
          hint: c.pronunciation,
          audioAssets: audioAssets,
          imageAssets: imageAssets,
          sourceNoteId: 'official:review:$cardId',
        );
      case AnkiPracticeShape.typeAnswer:
        return Interaction.typeTheWord(
          id: id,
          audioAsset: audioAssets.isNotEmpty ? audioAssets.first : '',
          prompt: term.isNotEmpty ? term : 'Type the word',
          expected: meaning,
        );
      case AnkiPracticeShape.expression:
      case AnkiPracticeShape.vocab:
      case AnkiPracticeShape.flip:
      case AnkiPracticeShape.fidelity:
        return Interaction.ankiCard(
          id: id,
          front: term,
          back: meaning,
          hint: c.pronunciation,
          audioAssets: audioAssets,
          imageAssets: imageAssets,
          sourceNoteId: 'official:review:$cardId',
        );
    }
  }

  Set<InteractionRenderer> _getRenderers() {
    if (widget.renderers != null && widget.renderers!.isNotEmpty) {
      return widget.renderers!;
    }
    if (getIt.isRegistered<Set<InteractionRenderer>>()) {
      return getIt<Set<InteractionRenderer>>();
    }
    return {
      AnkiCardRenderer(),
      MultipleChoiceRenderer(),
      MultiSelectRenderer(),
      FillBlankRenderer(),
      ListenAndPickRenderer(),
      TypeTheWordRenderer(),
      if (getIt.isRegistered<AudioController>())
        ShowWordRenderer(getIt<AudioController>()),
    };
  }

  void _onSubmit(
    bool correct, {
    String? userAnswerText,
    int? reviewQuality,
  }) {
    final interaction = _toInteraction(_classify());
    if (interaction is AnkiCard) {
      String rating;
      if (userAnswerText == AppStrings.reviewBinaryForgotten ||
          userAnswerText == AppStrings.reviewAgain ||
          reviewQuality == 1 ||
          !correct) {
        rating = 'again';
      } else {
        rating = 'good';
      }
      if (widget.phase == OfficialReviewPhase.showingQuestion) {
        widget.onShowAnswer();
      }
      widget.onRate(rating);
      return;
    }

    // Objective interactions:
    setState(() {
      _interactionState = InteractionState(
        submitted: true,
        correct: correct,
        userAnswerText: userAnswerText,
      );
    });
    if (widget.phase == OfficialReviewPhase.showingQuestion) {
      widget.onShowAnswer();
    }

    // Record mistake if wrong (MCQ, fill-blank, listen, etc.)
    final isSelfGraded = interaction is AnkiCard || interaction is AnkiHtmlCard;
    if (!correct && !isSelfGraded) {
      try {
        final mp = context.read<MistakeProvider?>();
        mp?.record(
          MistakeEntry(
            id: 'official-review-${widget.card.cardId}-${DateTime.now().millisecondsSinceEpoch}',
            lessonId: 'official-review',
            stageId: 'stage-review',
            interactionId: interaction.id,
            wordId: 'official-anki-review-c${widget.card.cardId}',
            interactionSnapshot: interaction,
            userAnswer: userAnswerText ?? '',
            correctAnswer: interactionCorrectAnswerLabel(interaction) ?? '',
            timestamp: DateTime.now(),
          ),
        );
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final classification = _classify();
    final interaction = _toInteraction(classification);
    final isAnswerPhase = widget.isAnswerVisible ||
        widget.phase == OfficialReviewPhase.showingAnswer;

    Widget content;
    if (interaction is AnkiCard) {
      content = _buildAnkiCardContent(interaction, classification, isAnswerPhase);
    } else {
      final renderers = _getRenderers();
      final renderer = lookupRenderer(renderers, interaction);
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          renderer.build(interaction, _interactionState, _onSubmit),
          if (_interactionState.submitted) ...[
            const SizedBox(height: 16),
            LessonCheckButton(
              label: AppStrings.lessonContinueUpper,
              enabled: true,
              onPressed: () {
                final rating =
                    _interactionState.correct == true ? 'good' : 'again';
                widget.onRate(rating);
              },
            ),
          ],
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: content,
        ),
      ),
    );
  }

  Widget _buildAnkiCardContent(
    AnkiCard interaction,
    AnkiPracticeClassification classification,
    bool isAnswerPhase,
  ) {
    return GestureDetector(
      onTap: isAnswerPhase ? null : widget.onShowAnswer,
      child: LessonPracticeCard(
        variant: isAnswerPhase
            ? LessonPracticeCardVariant.back
            : LessonPracticeCardVariant.front,
        appearAnimation: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 12),
            Text(
              interaction.front,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: TurnaTheme.textPrimaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            if (interaction.hint != null && interaction.hint!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                interaction.hint!,
                style: TextStyle(
                  fontSize: 18,
                  color: TurnaTheme.brandTeal,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (interaction.audioAssets.isNotEmpty ||
                interaction.imageAssets.isNotEmpty) ...[
              const SizedBox(height: 16),
              AnkiMediaStrip(
                audioAssets: interaction.audioAssets,
                imageAssets: interaction.imageAssets,
              ),
            ],
            const SizedBox(height: 24),
            if (isAnswerPhase) ...[
              const Divider(),
              const SizedBox(height: 16),
              Text(
                interaction.back,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
                textAlign: TextAlign.center,
              ),
              if (classification.example != null &&
                  classification.example!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius:
                        BorderRadius.circular(TurnaTheme.radiusMedium),
                  ),
                  child: Text(
                    classification.example!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ] else ...[
              const SizedBox(height: 16),
              Text(
                AppStrings.ankiShowAnswerFlip,
                style: TextStyle(
                  fontSize: 14,
                  color: TurnaTheme.textHintColor(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
