/// Progression state shared between the lesson viewmodel and renderers.
///
/// The renderer owns its **input** state (selected option, typed text, picked
/// tokens, etc.). The parent (the lesson viewmodel) owns **progression**
/// state — whether the user has submitted the current item, whether the
/// answer was correct, and what answer text to surface in feedback.
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
typedef OnInteractionSubmit = void Function(
  bool correct, {
  String? userAnswerText,
  int? reviewQuality,
});
