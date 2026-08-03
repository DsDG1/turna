// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/core/text_styles.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/lesson_practice_card.dart';
import 'package:turna/views/theme.dart';

/// Free-text translation. User types the translation of a source sentence.
/// Match is case-insensitive, whitespace-trimmed, and ignores trailing
/// punctuation. Hints are clickable chips that insert into the field.
@injectable
class TranslateSentenceRenderer extends InteractionRenderer {
  @override
  Type get handlesType => TranslateSentence;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as TranslateSentence;
    return _TranslateBody(
      source: i.source,
      expected: i.expected,
      hints: i.hints,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _TranslateBody extends StatefulWidget {
  final String source;
  final String expected;
  final List<String> hints;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _TranslateBody({
    required this.source,
    required this.expected,
    required this.hints,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_TranslateBody> createState() => _TranslateBodyState();
}

class _TranslateBodyState extends State<_TranslateBody> {
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

  static final _punctuation = RegExp(r'[.,!?;:"]');
  static final _whitespace = RegExp(r'\s+');

  bool _matches(String input) {
    final norm = input
        .replaceAll(_punctuation, '')
        .trim()
        .toLowerCase()
        .replaceAll(_whitespace, ' ');
    final target = widget.expected
        .replaceAll(_punctuation, '')
        .trim()
        .toLowerCase()
        .replaceAll(_whitespace, ' ');
    return norm == target;
  }

  void _applyHint(String hint) {
    final current = _controller.text;
    final needsSpace =
        current.isNotEmpty && !current.endsWith(' ') && !hint.startsWith(' ');
    // Updating the controller notifies ValueListenableBuilder — no setState.
    _controller.text = current + (needsSpace ? ' ' : '') + hint;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
  }

  void _trySubmit() {
    final text = _controller.text;
    if (widget.state.submitted || text.trim().isEmpty) return;
    widget.onSubmit(_matches(text), userAnswerText: text);
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppStrings.lessonTranslateCaption),
          LessonPracticeCard(
            variant: LessonPracticeCardVariant.surface,
            padding: const EdgeInsets.all(20),
            child: Text(
              widget.source,
              style: AppTextStyles.promptLg(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            enabled: !submitted,
            maxLines: 3,
            minLines: 1,
            style: TextStyle(
                fontSize: 18, color: TurnaTheme.textPrimaryColor(context)),
            decoration: InputDecoration(
              hintText: AppStrings.lessonTypeTranslation,
              filled: true,
              fillColor: submitted
                  ? (correct == true
                      ? TurnaTheme.success.withValues(alpha: 0.10)
                      : TurnaTheme.error.withValues(alpha: 0.08))
                  : TurnaTheme.inputFillColor(context),
            ),
          ),
          if (widget.hints.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in widget.hints)
                  ActionChip(
                    label: Text(h),
                    onPressed: submitted ? null : () => _applyHint(h),
                    backgroundColor:
                        TurnaTheme.peacockCyan.withValues(alpha: 0.12),
                    labelStyle: const TextStyle(
                      color: TurnaTheme.peacockDeep,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(TurnaTheme.radiusRound),
                      side: BorderSide.none,
                    ),
                  ),
              ],
            ),
          ],
          if (submitted && correct == false) ...[
            const SizedBox(height: 16),
            LessonCorrectAnswerBanner(
                label: AppStrings.lessonCorrectTranslation,
                answer: widget.expected),
          ],
          const SizedBox(height: 24),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final canSubmit = !submitted && value.text.trim().isNotEmpty;
              return LessonCheckButton(
                label: submitted
                    ? AppStrings.lessonChecked
                    : AppStrings.lessonCheck,
                enabled: canSubmit,
                onPressed: canSubmit ? _trySubmit : null,
              );
            },
          ),
        ],
      ),
    );
  }
}
