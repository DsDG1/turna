// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/core/text_styles.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/theme.dart';

/// Renderer for [Interaction.readingTrueFalse].
///
/// Renders the statement + True/False tiles. The lesson screen renders the
/// reading passage above and owns the post-submit Continue button.
@injectable
class ReadingTrueFalseRenderer extends InteractionRenderer {
  @override
  Type get handlesType => ReadingTrueFalse;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as ReadingTrueFalse;
    return _ReadingTrueFalseBody(
      statement: i.statement,
      answer: i.answer,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _ReadingTrueFalseBody extends StatefulWidget {
  final String statement;
  final bool answer;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _ReadingTrueFalseBody({
    required this.statement,
    required this.answer,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_ReadingTrueFalseBody> createState() => _ReadingTrueFalseBodyState();
}

class _ReadingTrueFalseBodyState extends State<_ReadingTrueFalseBody> {
  bool? _selectedBool;

  @override
  void initState() {
    super.initState();
    if (widget.state.submitted) _restoreSelected();
  }

  @override
  void didUpdateWidget(covariant _ReadingTrueFalseBody old) {
    super.didUpdateWidget(old);
    if (widget.state.submitted && !old.state.submitted) {
      _restoreSelected();
    }
  }

  void _restoreSelected() {
    final answer = widget.state.userAnswerText;
    if (answer == 'True') {
      _selectedBool = true;
    } else if (answer == 'False') {
      _selectedBool = false;
    } else {
      _selectedBool = widget.answer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionCaption('True or False'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: VarnamalaTheme.tintLight,
              borderRadius:
                  BorderRadius.circular(VarnamalaTheme.radiusLarge),
            ),
            child: Text(widget.statement, style: AppTextStyles.promptMd),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: InteractionOptionTile(
                  label: 'True',
                  isSelected: _selectedBool == true,
                  isCorrect: submitted && widget.answer == true,
                  isWrong:
                      submitted && correct == false && _selectedBool == true,
                  onTap: submitted
                      ? null
                      : () => setState(() => _selectedBool = true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InteractionOptionTile(
                  label: 'False',
                  isSelected: _selectedBool == false,
                  isCorrect: submitted && widget.answer == false,
                  isWrong: submitted &&
                      correct == false &&
                      _selectedBool == false,
                  onTap: submitted
                      ? null
                      : () => setState(() => _selectedBool = false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (!submitted)
            LessonCheckButton(
              label: 'CHECK',
              enabled: _selectedBool != null,
              onPressed: _selectedBool != null
                  ? () => widget.onSubmit(
                        _selectedBool == widget.answer,
                        userAnswerText: _selectedBool! ? 'True' : 'False',
                      )
                  : null,
            ),
        ],
      ),
    );
  }
}