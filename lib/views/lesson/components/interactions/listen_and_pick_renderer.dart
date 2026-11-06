// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/smart_speech.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/listening_audio_panel.dart';
import 'package:turna/views/lesson/components/interactions/interaction_fields.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/widgets/tts_feedback.dart';

/// Play audio (TTS) and pick the matching option. The [Interaction.audioAsset]
/// field is a wordId in current data; we look up the target-language term from the
/// vocab table and speak it via [FlutterTts].
@injectable
class ListenAndPickRenderer extends InteractionRenderer {
  @override
  Type get handlesType => ListenAndPick;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as ListenAndPick;
    return _ListenAndPickBody(
      audioAsset: i.audioAsset,
      prompt: i.prompt,
      options: i.options,
      correctIndex: i.correctIndex,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _ListenAndPickBody extends StatefulWidget {
  final String audioAsset;
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _ListenAndPickBody({
    required this.audioAsset,
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_ListenAndPickBody> createState() => _ListenAndPickBodyState();
}

class _ListenAndPickBodyState extends State<_ListenAndPickBody> {
  int? _picked;
  bool _hasPlayed = false;

  @override
  void initState() {
    super.initState();
    if (widget.state.submitted) _restorePicked();
    maybeAutoSpeak(_speak);
  }

  @override
  void didUpdateWidget(covariant _ListenAndPickBody old) {
    super.didUpdateWidget(old);
    if (widget.state.submitted && !old.state.submitted) {
      _restorePicked();
    }
  }

  void _restorePicked() {
    final answer = widget.state.userAnswerText;
    if (answer != null) {
      final idx = widget.options.indexOf(answer);
      _picked = idx >= 0 ? idx : widget.correctIndex;
    } else {
      _picked = widget.correctIndex;
    }
  }

  Future<void> _speak() async {
    final result =
        await getIt<AudioController>().speakWordWithResult(widget.audioAsset);
    if (!mounted) return;
    setState(() => _hasPlayed = true);
    showTtsFailureFeedback(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;
    final canSubmit = !submitted && _picked != null;

    // 按钮由页面底栏统一画; 这里只报"能不能提交 / 提交做什么".
    LessonActionScope.maybeOf(context)?.report(
      canSubmit: canSubmit,
      submit: canSubmit
          ? () => widget.onSubmit(
                _picked == widget.correctIndex,
                userAnswerText: widget.options[_picked!],
              )
          : null,
    );

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListeningAudioPanel(
            title: AppStrings.lessonListenAndPickCaption,
            prompt: widget.prompt,
            hasPlayed: _hasPlayed,
            onPlay: _speak,
          ),
          const SizedBox(height: 24),
          for (var idx = 0; idx < widget.options.length; idx++)
            InteractionOptionTile(
              label: widget.options[idx],
              index: idx + 1,
              isSelected: _picked == idx,
              isCorrect: submitted && idx == widget.correctIndex,
              isWrong: submitted && correct == false && _picked == idx,
              showDivider: idx < widget.options.length - 1,
              onTap: submitted ? null : () => setState(() => _picked = idx),
            ),
          if (submitted) ...[
            const SizedBox(height: 16),
            InteractionFeedbackPanel(
              correct: correct == true,
              userAnswer: _picked == null ? null : widget.options[_picked!],
              correctAnswer: widget.options[widget.correctIndex],
            ),
          ],
        ],
      ),
    );
  }
}
