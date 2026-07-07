// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:words625/views/theme.dart';

/// Pick one of N options. Submit locks the UI and colours correct/incorrect
/// choices using [InteractionState.correct].
@injectable
class MultipleChoiceRenderer extends InteractionRenderer {
  @override
  Type get handlesType => MultipleChoice;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as MultipleChoice;
    return _MultipleChoiceBody(
      prompt: i.prompt,
      options: i.options,
      correctIndex: i.correctIndex,
      imageAsset: i.imageAsset,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _MultipleChoiceBody extends StatefulWidget {
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String? imageAsset;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _MultipleChoiceBody({
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.imageAsset,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_MultipleChoiceBody> createState() => _MultipleChoiceBodyState();
}

class _MultipleChoiceBodyState extends State<_MultipleChoiceBody> {
  int? _picked;

  @override
  void initState() {
    super.initState();
    if (widget.state.submitted) _picked = widget.correctIndex;
  }

  @override
  void didUpdateWidget(covariant _MultipleChoiceBody old) {
    super.didUpdateWidget(old);
    if (widget.state.submitted && !old.state.submitted) {
      _picked = widget.correctIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;
    final canSubmit = !submitted && _picked != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            widget.prompt,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textPrimary,
            ),
          ),
          if (widget.imageAsset != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(VarnamalaTheme.radiusMedium),
              child: Image.asset(widget.imageAsset!, fit: BoxFit.cover),
            ),
          ],
          const SizedBox(height: 24),
          ..._buildOptions(submitted, correct),
          const SizedBox(height: 20),
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

  List<Widget> _buildOptions(bool submitted, bool? correct) {
    final widgets = <Widget>[];
    for (var idx = 0; idx < widget.options.length; idx++) {
      widgets.add(_OptionTile(
        label: widget.options[idx],
        isSelected: _picked == idx,
        isCorrect: submitted && idx == widget.correctIndex,
        isWrong:
            submitted && correct == false && _picked == idx,
        onTap: submitted
            ? null
            : () => setState(() => _picked = idx),
      ));
      if (idx < widget.options.length - 1) {
        widgets.add(const SizedBox(height: 10));
      }
    }
    return widgets;
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
    Color textColor = VarnamalaTheme.textPrimary;
    Widget? trailing;

    if (isCorrect) {
      border = VarnamalaTheme.success;
      background =
          VarnamalaTheme.success.withValues(alpha: 0.10);
      trailing = const Icon(Icons.check_circle, color: VarnamalaTheme.success);
    } else if (isWrong) {
      border = VarnamalaTheme.error;
      background = VarnamalaTheme.error.withValues(alpha: 0.08);
      trailing = const Icon(Icons.cancel, color: VarnamalaTheme.error);
    } else if (isSelected) {
      border = VarnamalaTheme.peacockTeal;
      background =
          VarnamalaTheme.peacockTeal.withValues(alpha: 0.06);
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: textColor,
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
