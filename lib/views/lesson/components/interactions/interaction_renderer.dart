// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/core/spacing.dart';
import 'package:varnamala/core/text_styles.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/views/theme.dart';

/// Snapshot of how the parent ([LessonViewModel]) wants the renderer to look.
///
/// The renderer owns its **input** state (selected option, typed text, picked
/// tokens, etc.). The parent owns **progression** state — whether the user has
/// submitted the current item, whether the answer was correct, and what
/// answer text to surface in feedback.
class InteractionState {
  /// True after the user has submitted this item at least once.
  final bool submitted;

  /// `true` if the user's answer matched, `false` if not, `null` if not yet
  /// submitted. Renderers read this to colour options / show a banner.
  final bool? correct;

  /// The raw answer the user entered. Used by free-text renderers to echo
  /// the input back in the feedback panel after a wrong attempt.
  final String? userAnswerText;

  const InteractionState({
    this.submitted = false,
    this.correct,
    this.userAnswerText,
  });

  static const InteractionState idle = InteractionState();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InteractionState &&
          runtimeType == other.runtimeType &&
          submitted == other.submitted &&
          correct == other.correct &&
          userAnswerText == other.userAnswerText;

  @override
  int get hashCode =>
      Object.hash(runtimeType, submitted, correct, userAnswerText);

  InteractionState copyWith({
    bool? submitted,
    bool? correct,
    String? userAnswerText,
  }) =>
      InteractionState(
        submitted: submitted ?? this.submitted,
        correct: correct ?? this.correct,
        userAnswerText: userAnswerText ?? this.userAnswerText,
      );
}

/// Stable identifier for an interaction within a lesson.
///
/// The viewmodel tracks completion by id, so we synthesise a stable id from
/// the parent stage's id and the item's own [id] field. When the item
/// carries no explicit id (legacy data), we fall back to `legacy-$index`
/// so legacy and modernised data never collide.
String interactionItemId(
  String stageId,
  String itemId,
  int fallbackIndex,
) {
  if (itemId.isNotEmpty) return '$stageId#$itemId';
  return '$stageId#legacy-$fallbackIndex';
}

/// Result of a renderer's submit. The renderer computes correctness locally
/// (it has the answer) and reports back; the viewmodel records completion and
/// decides whether to advance.
typedef OnInteractionSubmit = void Function(bool correct,
    {String? userAnswerText});

/// Plugin-style renderer. Each [Interaction] subclass maps to one renderer,
/// registered as `@injectable` and collected into a `Set<InteractionRenderer>`
/// at app start (see [lib/di/injection.dart]).
abstract class InteractionRenderer {
  /// The concrete Interaction type this renderer handles. Used by the
  /// dispatcher: `renderers.firstWhere((r) => r.handlesType == i.runtimeType)`.
  Type get handlesType;

  /// Whether this interaction auto-advances immediately on submit (no
  /// "Continue"/"Got It" button shown by the lesson screen). Types like
  /// [ShowWord] — which has no correctness check — override this to `true`.
  /// New auto-advancing types only override this getter; the screen never
  /// branches on a concrete interaction type.
  bool get autoAdvance => false;

  /// Build the widget for [interaction]. [state] drives feedback display;
  /// [onSubmit] is invoked once per submit with the correctness verdict.
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  );
}

/// Convenience: get the renderer for a specific interaction, or throw.
///
/// Matches on freezed **interface** types via `is` / sealed switch, not
/// `runtimeType` (which is the private `_$FooImpl` and never equals
/// `handlesType => Foo`).
InteractionRenderer lookupRenderer(
  Iterable<InteractionRenderer> renderers,
  Interaction interaction,
) {
  final target = _handlesTypeFor(interaction);
  return renderers.firstWhere(
    (r) => r.handlesType == target,
    orElse: () => throw StateError(
      'No InteractionRenderer registered for $target '
      '(${interaction.runtimeType}). Did you forget to @injectable it?',
    ),
  );
}

/// Public freezed interface type corresponding to [interaction].
Type _handlesTypeFor(Interaction interaction) {
  return switch (interaction) {
    ShowWord() => ShowWord,
    MultipleChoice() => MultipleChoice,
    MultiSelect() => MultiSelect,
    FillBlank() => FillBlank,
    TranslateSentence() => TranslateSentence,
    ListenAndPick() => ListenAndPick,
    TypeTheWord() => TypeTheWord,
    ListenOnly() => ListenOnly,
    ReorderSentence() => ReorderSentence,
    ReadingMcq() => ReadingMcq,
    ReadingTrueFalse() => ReadingTrueFalse,
    ReadingShortAnswer() => ReadingShortAnswer,
  };
}

/// Bottom action button shared by all graders (MCQ, FillBlank, Translate,
/// ListenAndPick, TypeTheWord, ReorderSentence). ShowWord has no button — it
/// auto-advances on card tap.
class LessonCheckButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  const LessonCheckButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              enabled ? VarnamalaTheme.peacockTeal : VarnamalaTheme.divider,
          foregroundColor:
              enabled ? VarnamalaTheme.textOnPrimary : VarnamalaTheme.textHint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.buttonLabel,
        ),
      ),
    );
  }
}

/// Default body chrome every renderer sits inside. Provides the standard
/// side padding + bottom safe area. Scrolling is owned by the lesson page's
/// outer [SingleChildScrollView] — this used to nest its own scroll view,
/// which double-wrapped FillBlank / Translate / TypeTheWord / Reading* and
/// caused nested-scroll jank. Centering padding only; no [LayoutBuilder]
/// (its `minHeight: maxHeight - 120` math broke under the outer scroll's
/// unbounded height constraint).
class InteractionBody extends StatelessWidget {
  final Widget child;

  const InteractionBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: child,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Shared widgets used by interaction renderers
// ──────────────────────────────────────────────────────────────

/// Selectable option tile for MCQ / pick-from-list interactions.
class InteractionOptionTile extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isCorrect;
  final bool isWrong;
  final VoidCallback? onTap;

  const InteractionOptionTile({
    super.key,
    required this.label,
    required this.isSelected,
    required this.isCorrect,
    required this.isWrong,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color border = VarnamalaTheme.borderMuted;
    Color background = VarnamalaTheme.cardBg(context);
    Widget? trailing;

    if (isCorrect) {
      border = VarnamalaTheme.success;
      background = VarnamalaTheme.success.withValues(alpha: 0.10);
      trailing =
          const Icon(Icons.check_circle, color: VarnamalaTheme.success);
    } else if (isWrong) {
      border = VarnamalaTheme.error;
      background = VarnamalaTheme.error.withValues(alpha: 0.08);
      trailing = const Icon(Icons.cancel, color: VarnamalaTheme.error);
    } else if (isSelected) {
      border = VarnamalaTheme.peacockTeal;
      background = VarnamalaTheme.peacockTeal.withValues(alpha: 0.06);
    }

    return Semantics(
      button: true,
      label: label,
      selected: isSelected,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border, width: 2),
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: VarnamalaTheme.textPrimaryColor(context),
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Correct-answer feedback banner shown after a wrong submission.
class LessonCorrectAnswerBanner extends StatelessWidget {
  final String label;
  final String answer;
  final bool showBorder;

  const LessonCorrectAnswerBanner({
    super.key,
    required this.label,
    required this.answer,
    this.showBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: VarnamalaTheme.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        border: showBorder
            ? Border.all(color: VarnamalaTheme.success.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: VarnamalaTheme.successDark),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  color: VarnamalaTheme.textPrimaryColor(context),
                ),
                children: [
                  TextSpan(text: '$label: '),
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

/// Circular speaker button that plays audio via TTS.
class SpeakerButton extends StatelessWidget {
  final VoidCallback onPressed;

  const SpeakerButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Play audio',
      child: Tooltip(
        message: 'Play audio',
        child: Material(
          color: VarnamalaTheme.peacockTeal,
          shape: const CircleBorder(),
          elevation: 4,
          shadowColor: VarnamalaTheme.peacockTeal.withValues(alpha: 0.4),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Icon(Icons.volume_up_rounded,
                  color: VarnamalaTheme.textOnPrimary, size: 36),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small uppercase caption rendered above the prompt in each interaction
/// body ("Fill in the blank", "Listen and pick", etc.). Centralises the
/// caption style + the bottom padding so renderers stay visually aligned.
class SectionCaption extends StatelessWidget {
  final String text;

  const SectionCaption(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.caption(context),
      ),
    );
  }
}
