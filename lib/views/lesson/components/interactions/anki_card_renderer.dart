// Flutter imports:
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/core/sm2.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/anki_media_strip.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/lesson_practice_card.dart';
import 'package:turna/core/theme.dart';

/// Anki-style flip card renderer. Shows the front, user taps "Show Answer",
/// then records the binary recall result: forgotten or remembered.
///
/// **No read-aloud, by design.** The app does not speak an Anki card: the card
/// is somebody else's content, its text is not a vocabulary entry the app is
/// teaching, and reading it aloud with the course voice was an addition rather
/// than a rendering of the card. What the card *does* carry — `[sound:]` clips
/// and images — still plays through [AnkiMediaStrip]; that is the card's own
/// media and is untouched. A card with no media is silent.
///
/// Face changes use a light scale pulse (shrink → grow) rather than a 3D
/// rotate, so word cards feel soft and the action row does not jump with
/// perspective height changes mid-flip.
@injectable
class AnkiCardRenderer extends InteractionRenderer {
  @override
  Type get handlesType => AnkiCard;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as AnkiCard;
    return _AnkiCardBody(
      front: i.front,
      back: i.back,
      hint: i.hint,
      frontImageAssets: i.frontImageAssets,
      frontAudioAssets: i.frontAudioAssets,
      backImageAssets: i.backImageAssets,
      backAudioAssets: i.backAudioAssets,
      legacyImageAssets: i.imageAssets,
      legacyAudioAssets: i.audioAssets,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _AnkiCardBody extends StatefulWidget {
  final String front;
  final String back;
  final String? hint;

  /// Media proven to belong to the question face.
  final List<String> frontImageAssets;
  final List<String> frontAudioAssets;

  /// Media proven to belong to the answer face.
  final List<String> backImageAssets;
  final List<String> backAudioAssets;

  /// Media whose face was not proven by the importer. Rendered on the answer
  /// face only, so an answer clip cannot play or be read before the reveal.
  final List<String> legacyImageAssets;
  final List<String> legacyAudioAssets;

  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _AnkiCardBody({
    required this.front,
    required this.back,
    this.hint,
    required this.frontImageAssets,
    required this.frontAudioAssets,
    required this.backImageAssets,
    required this.backAudioAssets,
    required this.legacyImageAssets,
    required this.legacyAudioAssets,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_AnkiCardBody> createState() => _AnkiCardBodyState();
}

class _AnkiCardBodyState extends State<_AnkiCardBody>
    with SingleTickerProviderStateMixin {
  /// Semantic / logical face after the user asks to reveal (or hide). The
  /// visible face still follows [_flipController] so mid-animation reverse
  /// keeps showing the correct side.
  bool _revealed = false;

  late AnimationController _flipController;

  /// Minimum scale at the midpoint of the pulse (1.0 → min → 1.0).
  static const double _pulseMinScale = 0.94;

  /// Reserved height for the action row so swapping "Show answer" ↔ grade
  /// buttons does not jump the layout. Covers caption + spacing + 48px row.
  static const double _actionAreaMinHeight = 88;

  /// Grade buttons only after the reveal pulse finishes — avoids a height
  /// stutter while the card is still animating.
  bool get _showGradeButtons =>
      _revealed && _flipController.status == AnimationStatus.completed;

  @override
  void initState() {
    super.initState();
    // Linear progress so the face swap stays at the true midpoint; easing is
    // applied only to the scale envelope.
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    )..addStatusListener(_onFlipStatus);
  }

  void _onFlipStatus(AnimationStatus status) {
    // Rebuild the action row when the pulse settles (or is dismissed).
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _flipController.removeStatusListener(_onFlipStatus);
    _flipController.dispose();
    super.dispose();
  }

  void _reveal() {
    if (_revealed || _flipController.isAnimating) return;
    _toggleFace();
  }

  void _toggleFace() {
    if (_flipController.isAnimating) return;
    final reveal = !_revealed;
    setState(() => _revealed = reveal);
    if (reveal) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
  }

  void _grade({
    required bool correct,
    required String label,
    required AnkiReviewRating rating,
  }) {
    widget.onSubmit(
      correct,
      userAnswerText: label,
      reviewQuality: rating.quality,
    );
  }

  /// Scale envelope: 1.0 at t=0/1, [_pulseMinScale] at t=0.5.
  double _pulseScale(double t) {
    final towardMid = t < 0.5 ? t * 2.0 : (1.0 - t) * 2.0;
    final eased = Curves.easeInOut.transform(towardMid.clamp(0.0, 1.0));
    return lerpDouble(1.0, _pulseMinScale, eased)!;
  }

  @override
  Widget build(BuildContext context) {
    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppStrings.lessonFlipCardCaption),
          // Front / Back card area
          Semantics(
            button: true,
            label: _revealed
                ? AppStrings.lessonTapToReturnFront
                : AppStrings.lessonTapToReveal,
            child: GestureDetector(
              key: const ValueKey('anki-flip-card-surface'),
              behavior: HitTestBehavior.opaque,
              onTap: _toggleFace,
              child: AnimatedBuilder(
                animation: _flipController,
                builder: (context, child) {
                  final t = _flipController.value;
                  // Front while t < 0.5 (including reverse: back shrinks first).
                  final showFront = t < 0.5;
                  final scale = _pulseScale(t);
                  return Transform.scale(
                    scale: scale,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.medium,
                    child:
                        showFront ? _buildFront(context) : _buildBack(context),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Hint (shown before reveal)
          if (!_revealed && widget.hint != null && widget.hint!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: TurnaTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        size: 16, color: TurnaTheme.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.hint!,
                        style: TextStyle(
                          fontSize: 13,
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Action buttons — fixed min height so grade row appearance does
          // not jump the column after the pulse.
          if (!widget.state.submitted)
            ConstrainedBox(
              constraints:
                  const BoxConstraints(minHeight: _actionAreaMinHeight),
              child: Align(
                alignment: Alignment.topCenter,
                child: _showGradeButtons
                    ? _buildGradeButtons()
                    : LessonCheckButton(
                        label: AppStrings.lessonShowAnswer,
                        enabled: !_revealed && !_flipController.isAnimating,
                        onPressed: _reveal,
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFront(BuildContext context) {
    return LessonPracticeCard(
      variant: LessonPracticeCardVariant.front,
      appearAnimation: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.style_rounded,
            size: 32,
            color: TurnaTheme.brandTeal.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            widget.front,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: TurnaTheme.textPrimaryColor(context),
                ),
          ),
          const SizedBox(height: 8),
          _buildMedia(
            audioAssets: widget.frontAudioAssets,
            imageAssets: widget.frontImageAssets,
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.lessonTapToReveal,
            style: const TextStyle(
              fontSize: 13,
              color: TurnaTheme.textHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBack(BuildContext context) {
    return LessonPracticeCard(
      variant: LessonPracticeCardVariant.back,
      appearAnimation: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 28,
            color: TurnaTheme.brandTeal.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          Text(
            widget.back,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: TurnaTheme.textPrimaryColor(context),
                ),
          ),
          const SizedBox(height: 8),
          _buildMedia(
            audioAssets: [
              ...widget.backAudioAssets,
              ...widget.legacyAudioAssets,
            ],
            imageAssets: [
              ...widget.backImageAssets,
              ...widget.legacyImageAssets,
            ],
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.lessonTapToReturnFront,
            style: const TextStyle(
              fontSize: 13,
              color: TurnaTheme.textHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedia({
    required List<String> audioAssets,
    required List<String> imageAssets,
  }) {
    if (audioAssets.isEmpty && imageAssets.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AnkiMediaStrip(
        audioAssets: audioAssets,
        imageAssets: imageAssets,
      ),
    );
  }

  Widget _buildGradeButtons() {
    return BinaryGradeRow(
      onForgotten: () => _grade(
        correct: false,
        label: AppStrings.reviewBinaryForgotten,
        rating: AnkiReviewRating.again,
      ),
      onRemembered: () => _grade(
        correct: true,
        label: AppStrings.reviewBinaryRemembered,
        rating: AnkiReviewRating.good,
      ),
    );
  }
}
