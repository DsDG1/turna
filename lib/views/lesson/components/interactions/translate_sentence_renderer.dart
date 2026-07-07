// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:words625/views/theme.dart';

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

  bool _matches(String input) {
    final norm = input
        .replaceAll(_punctuation, '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    final target = widget.expected
        .replaceAll(_punctuation, '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    return norm == target;
  }

  void _applyHint(String hint) {
    final current = _controller.text;
    final needsSpace = current.isNotEmpty &&
        !current.endsWith(' ') &&
        !hint.startsWith(' ');
    _controller.text = current + (needsSpace ? ' ' : '') + hint;
    _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;
    final canSubmit = !submitted && _controller.text.trim().isNotEmpty;

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Translate this sentence',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textHint,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
            ),
            child: Text(
              widget.source,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: VarnamalaTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            enabled: !submitted,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(fontSize: 18, color: VarnamalaTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Type the translation...',
              filled: true,
              fillColor: submitted
                  ? (correct == true
                      ? VarnamalaTheme.success.withValues(alpha: 0.10)
                      : VarnamalaTheme.error.withValues(alpha: 0.08))
                  : Colors.white,
            ),
            onChanged: (_) => setState(() {}),
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
                    backgroundColor: VarnamalaTheme.peacockCyan
                        .withValues(alpha: 0.12),
                    labelStyle: const TextStyle(
                      color: VarnamalaTheme.peacockDeep,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(VarnamalaTheme.radiusRound),
                      side: BorderSide.none,
                    ),
                  ),
              ],
            ),
          ],
          if (submitted && correct == false) ...[
            const SizedBox(height: 16),
            _CorrectTranslationBanner(answer: widget.expected),
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
}

class _CorrectTranslationBanner extends StatelessWidget {
  final String answer;
  const _CorrectTranslationBanner({required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: VarnamalaTheme.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
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
                  const TextSpan(text: 'Correct translation: '),
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
