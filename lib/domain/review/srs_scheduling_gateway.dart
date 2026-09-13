import 'package:turna/core/sm2.dart';
import 'package:turna/domain/course/srs_word.dart';

/// Scheduling operations the review ledger needs from the SRS layer.
///
/// Extracted so the domain layer can orchestrate reviews without depending
/// on the application-layer [SrsProvider] ChangeNotifier; the provider
/// implements this gateway and stays the single runtime implementation.
abstract class SrsSchedulingGateway {
  /// Authoritative registered-item state keyed by raw id.
  Map<String, SrsWord> get state;

  /// Due word count (cached; see the provider for invalidation rules).
  int get dueCount;

  /// Due expression count (cached alongside [dueCount]).
  int get expressionDueCount;

  /// Due legacy-Anki words (optionally evaluated at [now]).
  List<SrsWord> getDueAnkiWords([DateTime? now]);

  /// Preview next interval days for [outcome] without mutating state.
  int previewOutcomeDays(SrsWord word, ReviewOutcome outcome);

  /// Preview the next failed-review delay. `null` for non-FSRS schedulers.
  Future<int?> previewFailMinutesFor(SrsWord word, {DateTime? now});

  /// Binary pass/fail review of a word. Returns the updated word or `null`
  /// when the id is not registered.
  Future<SrsWord?> reviewWordOutcome(
    String wordId,
    ReviewOutcome outcome, {
    String? eventSourceKey,
  });

  /// Same as [reviewWordOutcome] but for the expression queue.
  Future<SrsWord?> reviewExpressionOutcome(
    String expressionId,
    ReviewOutcome outcome, {
    String? eventSourceKey,
  });

  /// Restore [previous] (exact snapshot) for a word; `previous == null`
  /// removes the registration. Idempotent via [eventSourceKey].
  Future<bool> rollbackWord(
    String wordId,
    SrsWord? previous, {
    String? eventSourceKey,
  });

  /// Same as [rollbackWord] but for the expression queue.
  Future<bool> rollbackExpression(
    String expressionId,
    SrsWord? previous, {
    String? eventSourceKey,
  });
}
