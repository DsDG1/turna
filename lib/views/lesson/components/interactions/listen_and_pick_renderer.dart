// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/application/audio_controller.dart';
import 'package:words625/core/text_styles.dart';
import 'package:words625/di/injection.dart';
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/views/lesson/components/interactions/interaction_renderer.dart';

/// Play audio (TTS) and pick the matching option. The [Interaction.audioAsset]
/// field is a wordId in current data; we look up the Swahili term from the
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

  @override
  void initState() {
    super.initState();
    if (widget.state.submitted) _restorePicked();
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
    await getIt<AudioController>().speakWord(widget.audioAsset);
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;
    final canSubmit = !submitted && _picked != null;

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionCaption('Listen and pick'),
          Center(
            child: SpeakerButton(onPressed: _speak),
          ),
          const SizedBox(height: 24),
          Text(
            widget.prompt,
            style: AppTextStyles.promptMd,
          ),
          const SizedBox(height: 20),
          for (var idx = 0; idx < widget.options.length; idx++) ...[
            InteractionOptionTile(
              label: widget.options[idx],
              isSelected: _picked == idx,
              isCorrect: submitted && idx == widget.correctIndex,
              isWrong: submitted && correct == false && _picked == idx,
              onTap: submitted
                  ? null
                  : () => setState(() => _picked = idx),
            ),
            if (idx < widget.options.length - 1)
              const SizedBox(height: 10),
          ],
          const SizedBox(height: 24),
          LessonCheckButton(
            label: submitted ? 'CHECKED' : 'CHECK',
            enabled: canSubmit,
            onPressed: canSubmit
                ? () => widget.onSubmit(_picked == widget.correctIndex,
                    userAnswerText: widget.options[_picked!])
                : null,
          ),
        ],
      ),
    );
  }
}
