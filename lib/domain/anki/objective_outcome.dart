import 'package:turna/domain/review/recall_outcome.dart';

/// Maps an objective item (MCQ, multi-select, cloze, type-answer, listen)
/// onto the product-wide binary recall outcome.
///
/// Structured items do not show a second "remember / forget" prompt.
RecallOutcome objectiveRecallOutcome({required bool correct}) {
  return correct ? RecallOutcome.remembered : RecallOutcome.forgotten;
}
