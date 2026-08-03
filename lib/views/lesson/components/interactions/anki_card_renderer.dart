// Flutter imports:
import 'dart:math' as math;

import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/application/smart_speech.dart';
import 'package:varnamala/core/language_detector.dart';
import 'package:varnamala/core/sm2.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/lesson/components/anki_media_strip.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/lesson/components/lesson_practice_card.dart';
import 'package:varnamala/views/theme.dart';

/// Anki-style flip card renderer. Shows the front, user taps "Show Answer",
/// then grades with Anki's four answer buttons: Again / Hard / Good / Easy.
///
/// Again is an unsuccessful recall; Hard, Good and Easy are successful
/// recalls with distinct scheduler qualities.
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
  bool _revealed = false;
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  /// Resolved TTS languages for the front/back pair (computed lazily). Null
  /// until the first speak / auto-speak call.
  ({String front, String back})? _pair;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 380),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _flipController,
        // Material 标准曲线, 收尾更柔, 避免 easeInOut 在中点的"顿一下".
        curve: const Cubic(0.4, 0.0, 0.2, 1.0),
      ),
    );
    _maybeAutoSpeakFront();
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
                animation: _flipAnimation,
                builder: (context, child) {
                  final angle = _flipAnimation.value * math.pi;
                  final showFront = angle < math.pi / 2;
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(angle),
                    child: showFront
                        ? _buildFront(context)
                        // 背面在中点之后淡入, 避免旋转过中点后内容"啪"地出现.
                        : AnimatedBuilder(
                            animation: _flipAnimation,
                            builder: (ctx, child) {
                              final backProgress = ((angle - math.pi / 2)
                                      .clamp(0.0, math.pi / 2)) /
                                  (math.pi / 2);
                              return Opacity(
                                opacity: backProgress,
                                child: Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..rotateY(math.pi),
                                  child: child,
                                ),
                              );
                            },
                            child: _buildBack(context),
                          ),
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
                  color: VarnamalaTheme.warning.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusSmall),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        size: 16, color: VarnamalaTheme.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.hint!,
                        style: TextStyle(
                          fontSize: 13,
                          color: VarnamalaTheme.textSecondaryColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Action buttons
          if (!widget.state.submitted) ...[
            if (!_revealed)
              LessonCheckButton(
                label: AppStrings.lessonShowAnswer,
                enabled: true,
                onPressed: _reveal,
              )
            else
              _buildGradeButtons(context),
          ],
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
            color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            widget.front,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: VarnamalaTheme.textPrimaryColor(context),
                ),
          ),
          const SizedBox(height: 8),
          IconButton(
            icon: const Icon(Icons.record_voice_over_rounded),
            color: VarnamalaTheme.peacockTeal,
            tooltip: AppStrings.lessonSpeakLabel,
            onPressed: _speakFront,
          ),
          _buildMedia(),
          const SizedBox(height: 12),
          Text(
            AppStrings.lessonTapToReveal,
            style: const TextStyle(
              fontSize: 13,
              color: VarnamalaTheme.textHint,
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
            color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          Text(
            widget.back,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: VarnamalaTheme.textPrimaryColor(context),
                ),
          ),
          const SizedBox(height: 8),
          IconButton(
            icon: const Icon(Icons.record_voice_over_rounded),
            color: VarnamalaTheme.peacockTeal,
            tooltip: AppStrings.lessonSpeakLabel,
            onPressed: _speakBack,
          ),
          _buildMedia(),
          const SizedBox(height: 12),
          Text(
            AppStrings.lessonTapToReturnFront,
            style: const TextStyle(
              fontSize: 13,
              color: VarnamalaTheme.textHint,
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
      children: [
        Text(
          AppStrings.lessonHowWellDidYouKnow,
          style: TextStyle(
            fontSize: 14,
            color: VarnamalaTheme.textSecondaryColor(context),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _GradeButton(
                label: AppStrings.reviewAgain,
                color: VarnamalaTheme.error,
                onPressed: () => _grade(
                  correct: false,
                  label: AppStrings.reviewAgain,
                  rating: AnkiReviewRating.again,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _GradeButton(
                label: AppStrings.reviewHard,
                color: VarnamalaTheme.warning,
                onPressed: () => _grade(
                  correct: true,
                  label: AppStrings.reviewHard,
                  rating: AnkiReviewRating.hard,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _GradeButton(
                label: AppStrings.reviewGood,
                color: VarnamalaTheme.success,
                onPressed: () => _grade(
                  correct: true,
                  label: AppStrings.reviewGood,
                  rating: AnkiReviewRating.good,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _GradeButton(
                label: AppStrings.reviewEasy,
                color: VarnamalaTheme.peacockTeal,
                onPressed: () => _grade(
                  correct: true,
                  label: AppStrings.reviewEasy,
                  rating: AnkiReviewRating.easy,
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
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.12),
          foregroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withValues(alpha: 0.4)),
          ),
        ),
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
