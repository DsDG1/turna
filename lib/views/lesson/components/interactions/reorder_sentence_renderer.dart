// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/theme.dart';

/// Arrange scrambled tokens into the canonical sentence. Tap a token in the
/// pool to move it to the answer row; tap a token in the answer row to send
/// it back. The order they were tapped becomes the user's answer.
///
/// We intentionally avoid drag-reorder for now — tap-to-move is robust on
/// small touch targets, accessible, and trivial to upgrade later by adding
/// long-press drag within the answer row.
@injectable
class ReorderSentenceRenderer extends InteractionRenderer {
  @override
  Type get handlesType => ReorderSentence;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as ReorderSentence;
    return _ReorderBody(
      scrambled: i.scrambled,
      correct: i.correct,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _ReorderBody extends StatefulWidget {
  final List<String> scrambled;
  final List<String> correct;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _ReorderBody({
    required this.scrambled,
    required this.correct,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_ReorderBody> createState() => _ReorderBodyState();
}

class _ReorderBodyState extends State<_ReorderBody> {
  /// Tokens still in the pool (not yet picked).
  late List<String> _pool;

  /// Tokens the user has chosen, in the order they tapped.
  late List<String> _picked;

  @override
  void initState() {
    super.initState();
    _pool = List.of(widget.scrambled);
    _picked = <String>[];
  }

  void _pick(String token) {
    if (widget.state.submitted) return;
    setState(() {
      _pool.remove(token);
      _picked.add(token);
    });
  }

  void _unpick(String token) {
    if (widget.state.submitted) return;
    setState(() {
      _picked.remove(token);
      _pool.add(token);
    });
  }

  bool _matches() {
    if (_picked.length != widget.correct.length) return false;
    for (var i = 0; i < widget.correct.length; i++) {
      if (_picked[i] != widget.correct[i]) return false;
    }
    return true;
  }

  String _formatAnswer() => _picked.join(' ');

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;
    final canSubmit = !submitted && _picked.length == widget.correct.length;

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppStrings.lessonArrangeWordsCaption),
          Text(
            AppStrings.lessonTapRightOrder,
            style: const TextStyle(
              fontSize: 13,
              color: VarnamalaTheme.textHint,
            ),
          ),
          const SizedBox(height: 20),
          _AnswerRow(
            tokens: _picked,
            onTapToken: _unpick,
            submitted: submitted,
            correct: correct,
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            AppStrings.lessonWordBank,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textHint,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          _TokenWrap(
            tokens: _pool,
            onTapToken: _pick,
            enabled: !submitted,
          ),
          if (submitted && correct == false) ...[
            const SizedBox(height: 16),
            LessonCorrectAnswerBanner(
                label: AppStrings.lessonCorrectOrder, answer: widget.correct.join(' ')),
          ],
          const SizedBox(height: 24),
          LessonCheckButton(
            label: submitted ? AppStrings.lessonChecked : AppStrings.lessonCheck,
            enabled: canSubmit,
            onPressed: canSubmit
                ? () => widget.onSubmit(_matches(),
                    userAnswerText: _formatAnswer())
                : null,
          ),
        ],
      ),
    );
  }
}

class _AnswerRow extends StatelessWidget {
  final List<String> tokens;
  final void Function(String) onTapToken;
  final bool submitted;
  final bool? correct;

  const _AnswerRow({
    required this.tokens,
    required this.onTapToken,
    required this.submitted,
    required this.correct,
  });

  @override
  Widget build(BuildContext context) {
    Color border = VarnamalaTheme.textHint.withValues(alpha: 0.30);
    Color background = VarnamalaTheme.cardBg(context);
    if (submitted) {
      border = correct == true
          ? VarnamalaTheme.success
          : VarnamalaTheme.error;
      background = (correct == true
              ? VarnamalaTheme.success
              : VarnamalaTheme.error)
          .withValues(alpha: 0.06);
    } else if (tokens.isNotEmpty) {
      border = VarnamalaTheme.peacockTeal;
      background = VarnamalaTheme.peacockTeal.withValues(alpha: 0.04);
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border, width: 2),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      ),
      child: tokens.isEmpty
          ? Center(
              child: Text(
                AppStrings.lessonTapWordToStart,
                style: TextStyle(
                  color: VarnamalaTheme.textHint.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in tokens)
                  _TokenChip(
                    label: t,
                    onTap: submitted ? null : () => onTapToken(t),
                    selected: true,
                  ),
              ],
            ),
    );
  }
}

class _TokenWrap extends StatelessWidget {
  final List<String> tokens;
  final void Function(String) onTapToken;
  final bool enabled;

  const _TokenWrap({
    required this.tokens,
    required this.onTapToken,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Key by position, not by token string: a scrambled sentence can
        // repeat a word ("the the", "I I"), and ValueKey(token) would collide
        // across siblings and trip MultiChildRenderObjectElement's duplicate-key
        // assertion. The index is stable for a given scramble.
        for (var i = 0; i < tokens.length; i++)
          _TokenChip(
            key: ValueKey(i),
            label: tokens[i],
            onTap: enabled ? () => onTapToken(tokens[i]) : null,
            selected: false,
          ),
      ],
    );
  }
}

class _TokenChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  const _TokenChip({
    super.key,
    required this.label,
    required this.onTap,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? VarnamalaTheme.peacockTeal
        : VarnamalaTheme.cardBg(context);
    final fg = selected
        ? VarnamalaTheme.textOnPrimary
        : VarnamalaTheme.textPrimaryColor(context);
    final border = selected
        ? VarnamalaTheme.peacockTeal
        : VarnamalaTheme.textHint.withValues(alpha: 0.3);

    return Semantics(
      button: true,
      label: label,
      selected: selected,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border, width: 1.5),
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusRound),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusRound),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
