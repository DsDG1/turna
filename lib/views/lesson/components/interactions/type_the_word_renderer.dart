// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/courses/languages/kannada_vocab.dart';
import 'package:words625/di/injection.dart';
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:words625/views/theme.dart';

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

  String _resolveSpeakText() {
    final v = kannadaVocabById[widget.audioAsset];
    return v?.term ?? widget.audioAsset;
  }

  Future<void> _speak() async {
    final tts = getIt<FlutterTts>();
    await tts.stop();
    await tts.speak(_resolveSpeakText());
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
          const Text(
            'Type what you hear',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textHint,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: _SpeakerButton(onPressed: _speak),
          ),
          const SizedBox(height: 24),
          Text(
            widget.prompt,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textPrimary,
            ),
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
                  : Colors.white,
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
            _CorrectAnswerBanner(answer: widget.expected),
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

class _SpeakerButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _SpeakerButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VarnamalaTheme.peacockTeal,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: VarnamalaTheme.peacockTeal.withValues(alpha: 0.4),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Icon(Icons.volume_up_rounded, color: Colors.white, size: 36),
        ),
      ),
    );
  }
}

class _CorrectAnswerBanner extends StatelessWidget {
  final String answer;
  const _CorrectAnswerBanner({required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: VarnamalaTheme.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: VarnamalaTheme.successDark),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 14,
                  color: VarnamalaTheme.textPrimary,
                ),
                children: [
                  const TextSpan(text: 'Correct answer: '),
                  TextSpan(
                    text: answer,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
