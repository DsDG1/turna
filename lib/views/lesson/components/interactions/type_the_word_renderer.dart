// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/smart_speech.dart';
import 'package:turna/core/turkish_text.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/listening_audio_panel.dart';
import 'package:turna/views/lesson/components/interactions/interaction_fields.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/widgets/tts_feedback.dart';

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
  bool _hasPlayed = false;

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
    maybeAutoSpeak(_speak);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _speak() async {
    final result =
        await getIt<AudioController>().speakWordWithResult(widget.audioAsset);
    if (!mounted) return;
    setState(() => _hasPlayed = true);
    showTtsFailureFeedback(context, result);
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

    _syncDraft(context);

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListeningAudioPanel(
            title: AppStrings.lessonTypeWhatYouHearCaption,
            prompt: widget.prompt,
            hasPlayed: _hasPlayed,
            onPlay: _speak,
            compact: true,
          ),
          const SizedBox(height: 24),
          // 大字号书写档与听写共用（interaction_fields 收口处）。
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
