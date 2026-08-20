/// Binary recall outcome representing the learner's self-evaluation.
///
/// Invariant: Product and UI layers only ever know binary recall (forgotten / remembered).
/// Quality numbers (1..5) and Anki ratings (Again/Hard/Good/Easy) are mapped at ledger boundaries.
enum RecallOutcome {
  /// Learner could not recall the answer (不记得 -> Again).
  forgotten,

  /// Learner successfully recalled the answer (记得 -> Good).
  remembered;

  /// True if remembered.
  bool get isSuccess => this == RecallOutcome.remembered;
}
