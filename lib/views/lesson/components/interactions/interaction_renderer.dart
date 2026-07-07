// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:words625/domain/course/interaction.dart';

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
/// the parent stage's id and the item's index in `Stage.items`. If the lesson
/// data ever carries a real item id, swap this for that.
String interactionItemId(String stageId, int index) => '$stageId#$index';

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

  /// Build the widget for [interaction]. [state] drives feedback display;
  /// [onSubmit] is invoked once per submit with the correctness verdict.
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  );
}

/// Convenience: get the renderer for a specific interaction, or throw.
InteractionRenderer lookupRenderer(
  Iterable<InteractionRenderer> renderers,
  Interaction interaction,
) {
  return renderers.firstWhere(
    (r) => r.handlesType == interaction.runtimeType,
    orElse: () => throw StateError(
      'No InteractionRenderer registered for '
      '${interaction.runtimeType}. Did you forget to @injectable it?',
    ),
  );
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
          backgroundColor: enabled
              ? const Color(0xFF1F727E)
              : const Color(0xFFEEF2F1),
          foregroundColor: enabled ? Colors.white : const Color(0xFF9CA3AF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

/// Default body chrome every renderer sits inside: scrolls, centers vertically,
/// and constrains width on tablet.
class InteractionBody extends StatelessWidget {
  final Widget child;

  const InteractionBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                MediaQuery.of(context).padding.vertical -
                120,
          ),
          child: child,
        ),
      ),
    );
  }
}
