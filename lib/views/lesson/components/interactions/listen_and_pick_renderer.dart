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

/// Play audio (TTS) and pick the matching option. The [Interaction.audioAsset]
/// field is a wordId in current data; we look up the Kannada term from the
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
    if (widget.state.submitted) _picked = widget.correctIndex;
  }

  @override
  void didUpdateWidget(covariant _ListenAndPickBody old) {
    super.didUpdateWidget(old);
    if (widget.state.submitted && !old.state.submitted) {
      _picked = widget.correctIndex;
    }
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

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;
    final canSubmit = !submitted && _picked != null;

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Listen and pick',
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
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          for (var idx = 0; idx < widget.options.length; idx++) ...[
            _OptionTile(
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
                ? () => widget.onSubmit(_picked == widget.correctIndex)
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

class _OptionTile extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isCorrect;
  final bool isWrong;
  final VoidCallback? onTap;

  const _OptionTile({
    required this.label,
    required this.isSelected,
    required this.isCorrect,
    required this.isWrong,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color border = VarnamalaTheme.textHint.withValues(alpha: 0.25);
    Color background = Colors.white;
    Widget? trailing;

    if (isCorrect) {
      border = VarnamalaTheme.success;
      background = VarnamalaTheme.success.withValues(alpha: 0.10);
      trailing = const Icon(Icons.check_circle, color: VarnamalaTheme.success);
    } else if (isWrong) {
      border = VarnamalaTheme.error;
      background = VarnamalaTheme.error.withValues(alpha: 0.08);
      trailing = const Icon(Icons.cancel, color: VarnamalaTheme.error);
    } else if (isSelected) {
      border = VarnamalaTheme.peacockTeal;
      background = VarnamalaTheme.peacockTeal.withValues(alpha: 0.06);
    }

    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border, width: 2),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: VarnamalaTheme.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }
}
