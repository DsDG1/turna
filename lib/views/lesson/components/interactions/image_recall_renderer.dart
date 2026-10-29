// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/core/sm2.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/anki_media_strip.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';

/// 看图回忆 (ADR 0057 §4): the image is the prompt, the learner recalls the
/// reading, then reveals and self-grades.
///
/// Only prompt-side images ever reach this renderer (the resolver refuses to
/// build it from an answer-side image), and [answerText] is not constructed
/// before the reveal — so the answer cannot be read out or screenshotted from
/// the question face.
@injectable
class ImageRecallRenderer extends InteractionRenderer {
  @override
  Type get handlesType => ImageRecall;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as ImageRecall;
    return _ImageRecallBody(
      imageAssets: i.imageAssets,
      answerText: i.answerText,
      hint: i.hint,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _ImageRecallBody extends StatefulWidget {
  final List<String> imageAssets;
  final String answerText;
  final String? hint;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _ImageRecallBody({
    required this.imageAssets,
    required this.answerText,
    this.hint,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_ImageRecallBody> createState() => _ImageRecallBodyState();
}

class _ImageRecallBodyState extends State<_ImageRecallBody> {
  bool _revealed = false;

  void _reveal() {
    if (_revealed) return;
    setState(() => _revealed = true);
  }

  void _grade({
    required bool correct,
    required String label,
    required AnkiReviewRating rating,
  }) {
    if (widget.state.submitted) return;
    widget.onSubmit(
      correct,
      userAnswerText: label,
      reviewQuality: rating.quality,
    );
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppStrings.lessonImageRecallCaption),
          const SizedBox(height: 8),
          Text(
            AppStrings.lessonImageRecallPrompt,
            textAlign: TextAlign.center,
            style: AppTextStyles.promptMd(context),
          ),
          const SizedBox(height: 20),
          AnkiMediaStrip(imageAssets: widget.imageAssets),
          if (!_revealed &&
              widget.hint != null &&
              widget.hint!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              widget.hint!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
          ],
          if (_revealed) ...[
            const SizedBox(height: 24),
            Text(
              widget.answerText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: TurnaTheme.brandTeal,
                  ),
            ),
          ],
          const SizedBox(height: 24),
          if (!submitted)
            _revealed
                ? BinaryGradeRow(
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
                  )
                : LessonCheckButton(
                    label: AppStrings.lessonShowAnswer,
                    enabled: true,
                    onPressed: _reveal,
                  ),
        ],
      ),
    );
  }
}
