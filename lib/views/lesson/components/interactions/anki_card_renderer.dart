// Flutter imports:
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/smart_speech.dart';
import 'package:turna/core/language_detector.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/anki_media_strip.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/lesson_practice_card.dart';
import 'package:turna/views/theme.dart';

/// Anki-style flip card renderer. Shows the front, user taps "Show Answer",
/// then records the binary recall result: forgotten or remembered.
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
      imageAssets: i.imageAssets,
      audioAssets: i.audioAssets,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _AnkiCardBody extends StatefulWidget {
  final String front;
  final String back;
  final String? hint;
  final List<String> imageAssets;
  final List<String> audioAssets;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _AnkiCardBody({
    required this.front,
    required this.back,
    this.hint,
    required this.imageAssets,
    required this.audioAssets,
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

  /// Resolved TTS languages for the front/back pair (computed lazily). Null
  /// until the first speak / auto-speak call.
  ({String front, String back})? _pair;

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
    _maybeAutoSpeakFront();
  }

  void _onFlipStatus(AnimationStatus status) {
    // Rebuild the action row when the pulse settles (or is dismissed).
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      if (mounted) setState(() {});
    }
  }

  /// Resolve the front/back TTS languages from the card text + active course.
  void _ensurePair() {
    if (_pair != null) return;
    final langs = currentSpeechLanguages();
    _pair = const LanguageDetector().detectCardPair(
      widget.front,
      widget.back,
      targetLanguage: langs.target,
      nativeLanguage: langs.native,
    );
  }

  void _speakFace(String text, String? lang) {
    if (text.trim().isEmpty) return;
    getIt<AudioController>().speak(text, languageCode: lang);
  }

  void _speakFront() {
    _ensurePair();
    _speakFace(widget.front, _pair?.front);
  }

  void _speakBack() {
    _ensurePair();
    _speakFace(widget.back, _pair?.back);
  }

  /// Auto-read the front face when the card first appears, if the course's
  /// auto-read toggle is on.
  void _maybeAutoSpeakFront() {
    if (!autoReadOnTapForActiveCourse()) return;
    _ensurePair();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _speakFace(widget.front, _pair?.front);
    });
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
      // Auto-read the back face on reveal when the course toggle is on.
      if (autoReadOnTapForActiveCourse()) {
        _ensurePair();
        _speakFace(widget.back, _pair?.back);
      }
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
                    ? _buildGradeButtons(context)
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
          IconButton(
            icon: const Icon(Icons.record_voice_over_rounded),
            color: TurnaTheme.brandTeal,
            tooltip: AppStrings.lessonSpeakLabel,
            onPressed: _speakFront,
          ),
          _buildMedia(),
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
          IconButton(
            icon: const Icon(Icons.record_voice_over_rounded),
            color: TurnaTheme.brandTeal,
            tooltip: AppStrings.lessonSpeakLabel,
            onPressed: _speakBack,
          ),
          _buildMedia(),
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

  Widget _buildMedia() {
    if (widget.audioAssets.isEmpty && widget.imageAssets.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AnkiMediaStrip(
        audioAssets: widget.audioAssets,
        imageAssets: widget.imageAssets,
      ),
    );
  }

  Widget _buildGradeButtons(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _GradeButton(
                label: AppStrings.reviewBinaryForgotten,
                color: TurnaTheme.error,
                onPressed: () => _grade(
                  correct: false,
                  label: AppStrings.reviewBinaryForgotten,
                  rating: AnkiReviewRating.again,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _GradeButton(
                label: AppStrings.reviewBinaryRemembered,
                color: TurnaTheme.brandTeal,
                onPressed: () => _grade(
                  correct: true,
                  label: AppStrings.reviewBinaryRemembered,
                  rating: AnkiReviewRating.good,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GradeButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _GradeButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        // styleFrom treats elevation as a base level (pressed: +6); pin all states flat.
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.12),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withValues(alpha: 0.4)),
          ),
        ).copyWith(elevation: const WidgetStatePropertyAll<double>(0)),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
