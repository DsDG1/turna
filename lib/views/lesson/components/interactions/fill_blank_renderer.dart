// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:words625/views/theme.dart';

/// Fill in a blanked word in a sentence. The data uses `_____` to mark the
/// gap; we replace the first occurrence with a tappable [TextField]. Matching
/// is case-insensitive and whitespace-trimmed.
@injectable
class FillBlankRenderer extends InteractionRenderer {
  @override
  Type get handlesType => FillBlank;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as FillBlank;
    return _FillBlankBody(
      sentence: i.sentence,
      answer: i.answer,
      hint: i.hint,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _FillBlankBody extends StatefulWidget {
  final String sentence;
  final String answer;
  final String? hint;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _FillBlankBody({
    required this.sentence,
    required this.answer,
    required this.hint,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_FillBlankBody> createState() => _FillBlankBodyState();
}

class _FillBlankBodyState extends State<_FillBlankBody> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

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
    _focus.dispose();
    super.dispose();
  }

  bool _matches(String input) =>
      input.trim().toLowerCase() == widget.answer.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;
    final canSubmit = !submitted && _controller.text.trim().isNotEmpty;

    final (before, after) = _splitOnBlank(widget.sentence);
    final inputBoxColor = submitted
        ? (correct == true
            ? VarnamalaTheme.success.withValues(alpha: 0.10)
            : VarnamalaTheme.error.withValues(alpha: 0.08))
        : Colors.white;

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Fill in the blank',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textHint,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                fontSize: 22,
                height: 1.4,
                color: VarnamalaTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              children: [
                TextSpan(text: before),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 100),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: inputBoxColor,
                        border: Border.all(
                          color: submitted
                              ? (correct == true
                                  ? VarnamalaTheme.success
                                  : VarnamalaTheme.error)
                              : VarnamalaTheme.peacockTeal,
                          width: 2,
                        ),
                        borderRadius:
                            BorderRadius.circular(VarnamalaTheme.radiusSmall),
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        enabled: !submitted,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: VarnamalaTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          filled: false,
                          hintText: '___',
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          if (canSubmit) {
                            widget.onSubmit(
                              _matches(_controller.text),
                              userAnswerText: _controller.text,
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
                TextSpan(text: after),
              ],
            ),
          ),
          if (widget.hint != null && widget.hint!.isNotEmpty) ...[
            const SizedBox(height: 20),
            _HintChip(hint: widget.hint!),
          ],
          if (submitted && correct == false) ...[
            const SizedBox(height: 16),
            _CorrectAnswerBanner(answer: widget.answer),
          ],
          const SizedBox(height: 24),
          LessonCheckButton(
            label: submitted ? 'CHECKED' : 'CHECK',
            enabled: canSubmit,
            onPressed: canSubmit
                ? () => widget.onSubmit(
                      _matches(_controller.text),
                      userAnswerText: _controller.text,
                    )
                : null,
          ),
        ],
      ),
    );
  }

  (String, String) _splitOnBlank(String s) {
    const marker = '_____';
    final idx = s.indexOf(marker);
    if (idx < 0) return (s, '');
    return (s.substring(0, idx), s.substring(idx + marker.length));
  }
}

class _HintChip extends StatelessWidget {
  final String hint;
  const _HintChip({required this.hint});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: VarnamalaTheme.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusRound),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lightbulb_outline,
                size: 16, color: VarnamalaTheme.warning),
            const SizedBox(width: 6),
            Text(
              hint,
              style: const TextStyle(
                fontSize: 13,
                color: VarnamalaTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CorrectAnswerBanner extends StatelessWidget {
  final String answer;
  const _CorrectAnswerBanner({required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: VarnamalaTheme.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        border: Border.all(
            color: VarnamalaTheme.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: VarnamalaTheme.successDark),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 14,
                  color: VarnamalaTheme.textPrimary,
                ),
                children: [
                  const TextSpan(text: 'Correct answer: '),
                  TextSpan(
                    text: answer,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
