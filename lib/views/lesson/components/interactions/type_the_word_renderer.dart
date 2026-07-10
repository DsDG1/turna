// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/core/text_styles.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/theme.dart';

/// Play audio, then type what was heard. Match is case-insensitive and
/// whitespace-trimmed.
@injectable
class TypeTheWordRenderer extends InteractionRenderer {
  @override
  Type get handlesType => TypeTheWord;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as TypeTheWord;
    return _TypeTheWordBody(
      audioAsset: i.audioAsset,
      prompt: i.prompt,
      expected: i.expected,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _TypeTheWordBody extends StatefulWidget {
  final String audioAsset;
  final String prompt;
  final String expected;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _TypeTheWordBody({
    required this.audioAsset,
    required this.prompt,
    required this.expected,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_TypeTheWordBody> createState() => _TypeTheWordBodyState();
}

class _TypeTheWordBodyState extends State<_TypeTheWordBody> {
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

  Future<void> _speak() async {
    await getIt<AudioController>().speakWord(widget.audioAsset);
  }

  bool _matches(String input) =>
      input.trim().toLowerCase() == widget.expected.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;
    final canSubmit = !submitted && _controller.text.trim().isNotEmpty;

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionCaption('Type what you hear'),
          Center(
            child: SpeakerButton(onPressed: _speak),
          ),
          const SizedBox(height: 24),
          Text(
            widget.prompt,
            textAlign: TextAlign.center,
            style: AppTextStyles.promptMd(context),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            enabled: !submitted,
            autofocus: !submitted,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: VarnamalaTheme.textPrimary,
              letterSpacing: 0.5,
            ),
            decoration: InputDecoration(
              hintText: 'Type here...',
              filled: true,
              fillColor: submitted
                  ? (correct == true
                      ? VarnamalaTheme.success.withValues(alpha: 0.10)
                      : VarnamalaTheme.error.withValues(alpha: 0.08))
                  : VarnamalaTheme.inputFillColor(context),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (canSubmit) {
                widget.onSubmit(
                  _matches(_controller.text),
                  userAnswerText: _controller.text,
                );
              }
            },
          ),
          if (submitted && correct == false) ...[
            const SizedBox(height: 16),
            LessonCorrectAnswerBanner(
                label: 'Correct answer', answer: widget.expected),
          ],
          const SizedBox(height: 24),
          LessonCheckButton(
            label: submitted ? 'CHECKED' : 'CHECK',
            enabled: canSubmit,
            onPressed: canSubmit
                ? () => widget.onSubmit(
                      _matches(_controller.text),
                      userAnswerText: _controller.text,
                    )
                : null,
          ),
        ],
      ),
    );
  }
}
