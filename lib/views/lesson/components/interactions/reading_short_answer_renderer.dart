// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/turkish_text.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_fields.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/widgets/session_shell.dart';

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

  /// 文本类题型的"能否提交"来自 controller, 输入变化不会重建父 widget ——
  /// 所以既要 build 时同步一次首帧, 也要监听输入变化.
  void _syncDraft(BuildContext context) {
    final canSubmit =
        !widget.state.submitted && _controller.text.trim().isNotEmpty;
    LessonActionScope.maybeOf(context)?.report(
      canSubmit: canSubmit,
      submit: canSubmit ? _trySubmit : null,
    );
  }

  void _onTextChanged() {
    if (!mounted) return;
    _syncDraft(context);
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    if (widget.state.submitted && widget.state.userAnswerText != null) {
      _controller.text = widget.state.userAnswerText!;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  bool _matches(String input) =>
      foldTurkish(input.trim()) == foldTurkish(widget.expectedAnswer.trim());

  void _trySubmit() {
    final text = _controller.text;
    if (widget.state.submitted || text.trim().isEmpty) return;
    widget.onSubmit(_matches(text), userAnswerText: text);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;

    _syncDraft(context);

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppStrings.lessonShortAnswerCaption),
          // 问题在纸面画布上, 与阅读原文（页面级折叠卡）明确接续（§7.1 阅读理解）。
          SessionRecallCanvas(
            minHeight: 140,
            padding: const EdgeInsets.all(20),
            child: Text(
              widget.prompt,
              style: AppTextStyles.promptMd(context),
            ),
          ),
          const SizedBox(height: 24),
          InteractionTextField(
            controller: _controller,
            verdict:
                interactionVerdictOf(submitted: submitted, correct: correct),
            enabled: !submitted,
            autofocus: !submitted,
            hintText: AppStrings.lessonTypeYourAnswer,
            onSubmitted: (_) => _trySubmit(),
          ),
          if (submitted) ...[
            const SizedBox(height: 16),
            InteractionFeedbackPanel(
              correct: correct == true,
              userAnswer: widget.state.userAnswerText,
              correctAnswer: widget.expectedAnswer,
            ),
          ],
        ],
      ),
    );
  }
}
