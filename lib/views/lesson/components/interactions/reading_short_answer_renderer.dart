// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/core/text_styles.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/theme.dart';

/// Renderer for [Interaction.readingShortAnswer].
///
/// Renders a free-text answer field. The lesson screen renders the reading
/// passage above and owns the post-submit Continue button.
@injectable
class ReadingShortAnswerRenderer extends InteractionRenderer {
  @override
  Type get handlesType => ReadingShortAnswer;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as ReadingShortAnswer;
    return _ReadingShortAnswerBody(
      prompt: i.prompt,
      expectedAnswer: i.expectedAnswer,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _ReadingShortAnswerBody extends StatefulWidget {
  final String prompt;
  final String expectedAnswer;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _ReadingShortAnswerBody({
    required this.prompt,
    required this.expectedAnswer,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_ReadingShortAnswerBody> createState() =>
      _ReadingShortAnswerBodyState();
}

class _ReadingShortAnswerBodyState extends State<_ReadingShortAnswerBody> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.state.submitted && widget.state.userAnswerText != null) {
      _controller.text = widget.state.userAnswerText!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _matches(String input) =>
      input.trim().toLowerCase() ==
      widget.expectedAnswer.trim().toLowerCase();

  void _trySubmit() {
    final text = _controller.text;
    if (widget.state.submitted || text.trim().isEmpty) return;
    widget.onSubmit(_matches(text), userAnswerText: text);
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionCaption('Short answer'),
          Text(widget.prompt, style: AppTextStyles.promptMd(context)),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            enabled: !submitted,
            autofocus: !submitted,
            style: TextStyle(
              fontSize: 18,
              color: VarnamalaTheme.textPrimaryColor(context),
            ),
            decoration: InputDecoration(
              hintText: 'Type your answer...',
              filled: true,
              fillColor: submitted
                  ? (correct == true
                      ? VarnamalaTheme.success.withValues(alpha: 0.10)
                      : VarnamalaTheme.error.withValues(alpha: 0.08))
                  : VarnamalaTheme.inputFillColor(context),
            ),
            onSubmitted: (_) => _trySubmit(),
          ),
          if (submitted && correct == false) ...[
            const SizedBox(height: 16),
            LessonCorrectAnswerBanner(
              label: 'Correct answer',
              answer: widget.expectedAnswer,
            ),
          ],
          const SizedBox(height: 24),
          if (!submitted)
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                final canSubmit = value.text.trim().isNotEmpty;
                return LessonCheckButton(
                  label: 'CHECK',
                  enabled: canSubmit,
                  onPressed: canSubmit ? _trySubmit : null,
                );
              },
            ),
        ],
      ),
    );
  }
}
