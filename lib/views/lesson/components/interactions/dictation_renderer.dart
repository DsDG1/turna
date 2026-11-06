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
import 'package:turna/views/lesson/components/interactions/interaction_fields.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/widgets/session_shell.dart';

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
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
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

    _syncDraft(context);

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SessionRecallCanvas(
            minHeight: 160,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.hearing_rounded,
                      size: 18,
                      color: TurnaTheme.brandTeal,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.lessonTypeWhatYouHearCaption,
                      style: AppTextStyles.caption(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  AppStrings.lessonDictationPrompt,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.promptMd(context),
                ),
                const SizedBox(height: 18),
                Center(
                  child: AnkiMediaStrip(audioAssets: widget.audioAssets),
                ),
              ],
            ),
          ),
          if (!submitted && widget.hint != null && widget.hint!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Center(child: InteractionHintChip(label: widget.hint!)),
          ],
          const SizedBox(height: 24),
          InteractionTextField(
            controller: _controller,
            verdict:
                interactionVerdictOf(submitted: submitted, correct: correct),
            enabled: !submitted,
            autofocus: !submitted,
            textAlign: TextAlign.center,
            largeStyle: true,
            hintText: AppStrings.lessonTypeHere,
            onSubmitted: (_) => _trySubmit(),
          ),
          if (submitted) ...[
            const SizedBox(height: 16),
            InteractionFeedbackPanel(
              correct: correct == true,
              userAnswer: widget.state.userAnswerText,
              correctAnswer: widget.expected,
            ),
          ],
        ],
      ),
    );
  }
}
