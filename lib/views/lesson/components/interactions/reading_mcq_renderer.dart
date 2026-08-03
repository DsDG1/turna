// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/core/text_styles.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';

/// Renderer for [Interaction.readingMcq].
///
/// Renders the comprehension prompt + options. The lesson screen renders the
/// reading passage above this widget and owns the post-submit Continue
/// button (this renderer only renders the pre-submit CHECK button).
@injectable
class ReadingMcqRenderer extends InteractionRenderer {
  @override
  Type get handlesType => ReadingMcq;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as ReadingMcq;
    return _ReadingMcqBody(
      prompt: i.prompt,
      options: i.options,
      correctIndex: i.correctIndex,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _ReadingMcqBody extends StatefulWidget {
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _ReadingMcqBody({
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_ReadingMcqBody> createState() => _ReadingMcqBodyState();
}

class _ReadingMcqBodyState extends State<_ReadingMcqBody> {
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    if (widget.state.submitted) _restoreSelected();
  }

  @override
  void didUpdateWidget(covariant _ReadingMcqBody old) {
    super.didUpdateWidget(old);
    if (widget.state.submitted && !old.state.submitted) {
      _restoreSelected();
    }
  }

  void _restoreSelected() {
    final answer = widget.state.userAnswerText;
    if (answer != null) {
      final idx = widget.options.indexOf(answer);
      _selectedIndex = idx >= 0 ? idx : widget.correctIndex;
    } else {
      _selectedIndex = widget.correctIndex;
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
          SectionCaption(AppStrings.lessonReadingComprehensionCaption),
          Text(widget.prompt, style: AppTextStyles.promptMd(context)),
          const SizedBox(height: 20),
          for (var idx = 0; idx < widget.options.length; idx++) ...[
            InteractionOptionTile(
              label: widget.options[idx],
              isSelected: _selectedIndex == idx,
              isCorrect: submitted && idx == widget.correctIndex,
              isWrong: submitted && correct == false && _selectedIndex == idx,
              onTap:
                  submitted ? null : () => setState(() => _selectedIndex = idx),
            ),
            if (idx < widget.options.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 24),
          if (!submitted)
            LessonCheckButton(
              label: AppStrings.lessonCheck,
              enabled: _selectedIndex != null,
              onPressed: _selectedIndex != null
                  ? () => widget.onSubmit(
                        _selectedIndex == widget.correctIndex,
                        userAnswerText: widget.options[_selectedIndex!],
                      )
                  : null,
            ),
        ],
      ),
    );
  }
}
