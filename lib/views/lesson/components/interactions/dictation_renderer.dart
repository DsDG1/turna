// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turkish_text.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/anki_media_strip.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';

/// 听写 (ADR 0057 §4): audio only on the question face, typed answer.
///
/// Deliberately separate from [TypeTheWordRenderer]: that one renders a text
/// prompt, which on a dictation card would hand the learner the answer. Here
/// nothing but the media strip and the input field exists before submit — no
/// answer text, no caption carrying the word, no alt text.
@injectable
class DictationRenderer extends InteractionRenderer {
  @override
  Type get handlesType => Dictation;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as Dictation;
    return _DictationBody(
      audioAssets: i.audioAssets,
      expected: i.expected,
      hint: i.hint,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _DictationBody extends StatefulWidget {
  final List<String> audioAssets;
  final String expected;
  final String? hint;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _DictationBody({
    required this.audioAssets,
    required this.expected,
    this.hint,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_DictationBody> createState() => _DictationBodyState();
}

class _DictationBodyState extends State<_DictationBody> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _matches(String input) =>
      foldTurkish(input.trim()) == foldTurkish(widget.expected.trim());

  void _trySubmit() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    widget.onSubmit(_matches(text), userAnswerText: text);
    // Drop the keyboard so the CONTINUE banner is not covered.
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppStrings.lessonTypeWhatYouHearCaption),
          const SizedBox(height: 8),
          Text(
            AppStrings.lessonDictationPrompt,
            textAlign: TextAlign.center,
            style: AppTextStyles.promptMd(context),
          ),
          const SizedBox(height: 20),
          AnkiMediaStrip(audioAssets: widget.audioAssets),
          if (!submitted && widget.hint != null && widget.hint!.isNotEmpty) ...[
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
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            enabled: !submitted,
            autofocus: !submitted,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: TurnaTheme.textPrimaryColor(context),
              letterSpacing: 0.5,
            ),
            decoration: InputDecoration(
              hintText: AppStrings.lessonTypeHere,
              filled: true,
              fillColor: submitted
                  ? (correct == true
                      ? TurnaTheme.success.withValues(alpha: 0.10)
                      : TurnaTheme.error.withValues(alpha: 0.08))
                  : TurnaTheme.inputFillColor(context),
            ),
            onSubmitted: (_) => _trySubmit(),
          ),
          if (submitted && correct == false) ...[
            const SizedBox(height: 16),
            LessonCorrectAnswerBanner(
              label: AppStrings.lessonCorrectAnswer,
              answer: widget.expected,
            ),
          ],
          if (!submitted) ...[
            const SizedBox(height: 24),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                final canSubmit = value.text.trim().isNotEmpty;
                return LessonCheckButton(
                  label: AppStrings.lessonCheck,
                  enabled: canSubmit,
                  onPressed: canSubmit ? _trySubmit : null,
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
