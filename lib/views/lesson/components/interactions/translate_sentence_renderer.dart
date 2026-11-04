// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/turkish_text.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_fields.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/widgets/session_shell.dart';

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
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  static final _punctuation = RegExp(r'[.,!?;:"]');
  static final _whitespace = RegExp(r'\s+');

  bool _matches(String input) {
    final norm = foldTurkish(
      input.replaceAll(_punctuation, '').trim().replaceAll(_whitespace, ' '),
    );
    final target = foldTurkish(
      widget.expected
          .replaceAll(_punctuation, '')
          .trim()
          .replaceAll(_whitespace, ' '),
    );
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
          SectionCaption(AppStrings.lessonTranslateCaption),
          // 完整上下文（源句）在纸面画布上（§7.1 输入族）。
          SessionRecallCanvas(
            minHeight: 140,
            padding: const EdgeInsets.all(20),
            child: Text(
              widget.source,
              style: AppTextStyles.promptLg(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 明确书写区（§7.1「下方是明确书写区」）。
          InteractionTextField(
            controller: _controller,
            verdict: interactionVerdictOf(submitted: submitted, correct: correct),
            enabled: !submitted,
            maxLines: 3,
            minLines: 1,
            hintText: AppStrings.lessonTypeTranslation,
          ),
          if (widget.hints.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // 提示词是可点追加的语言材料, 与词块同一视觉语汇
                // （不再手调 ActionChip 配色）。
                for (final h in widget.hints)
                  WordChip(
                    label: h,
                    onTap: submitted ? null : () => _applyHint(h),
                  ),
              ],
            ),
          ],
          if (submitted) ...[
            const SizedBox(height: 16),
            InteractionFeedbackPanel(
              correct: correct == true,
              userAnswer: widget.state.userAnswerText,
              correctAnswer: widget.expected,
              correctAnswerLabel: AppStrings.lessonCorrectTranslation,
            ),
          ],
        ],
      ),
    );
  }
}
