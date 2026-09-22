// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/smart_speech.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/turkish_text.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/core/theme.dart';

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
    maybeAutoSpeak(_speak);
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
      foldTurkish(input.trim()) == foldTurkish(widget.expected.trim());

  void _trySubmit() {
    final text = _controller.text;
    if (widget.state.submitted || text.trim().isEmpty) return;
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
                label: AppStrings.lessonCorrectAnswer, answer: widget.expected),
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
