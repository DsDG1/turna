import 'package:flutter/material.dart';
import 'package:turna/application/accessibility_capabilities.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/anki_media_strip.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
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

  /// The practice review surface renders official cards as plain flip
  /// cards (doc 37 R2: reading the projection index on the review side is
  /// a separate project; the old per-card classifier never ran here
  /// anyway — the shape was hard-coded flip).
  Interaction _cardInteraction() {
    final cardId = widget.card.cardId;
    final rawQ = widget.rawQuestionHtml.isNotEmpty
        ? widget.rawQuestionHtml
        : 'Card $cardId';
    return Interaction.ankiCard(
      id: 'official-review-card-$cardId',
      front: rawQ,
      back: widget.rawAnswerHtml,
      sourceNoteId: 'official:review:$cardId',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAnswerPhase = widget.isAnswerVisible ||
        widget.phase == OfficialReviewPhase.showingAnswer;
    final cardTextScale = cardTextScaleOf(context);

    final ankiCard = _cardInteraction() as AnkiCard;
    final content = _buildAnkiCardContent(
      ankiCard,
      isAnswerPhase,
      cardTextScale,
    );

    // Widen the card lane as text grows so large scales get more horizontal
    // room instead of wrapping into slivers.
    var effectiveScale = MediaQuery.textScalerOf(context).scale(1);
    final cardScale = cardTextScale / 100.0;
    if (cardScale > effectiveScale) effectiveScale = cardScale;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 600 * effectiveScale),
          child: content,
        ),
      ),
    );
  }

  Widget _buildAnkiCardContent(
    AnkiCard interaction,
    bool isAnswerPhase,
    int cardTextScale,
  ) {
    // The card body follows the card text scale (matching the WebView review
    // tracks), replacing the global UI scaler for this subtree only.
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(cardTextScale / 100.0)),
      child: GestureDetector(
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
      ),
    );
  }
}
