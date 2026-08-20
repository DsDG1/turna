import 'package:turna/domain/review/recall_outcome.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/review_source.dart';

/// Authoritative next-due interval preview calculated by the ledger.
class ReviewPreview {
  final String intervalLabel;
  final Duration? estimatedInterval;
  final DateTime? nextDueAt;

  const ReviewPreview({
    required this.intervalLabel,
    this.estimatedInterval,
    this.nextDueAt,
  });

  @override
  String toString() => 'ReviewPreview($intervalLabel, nextDue: $nextDueAt)';
}

/// Immutable receipt returned upon answering a card, enabling idempotent undo.
class ReviewEventReceipt {
  final String eventId;
  final ReviewSource source;
  final ReviewSchedulingKey schedulingKey;
  final RecallOutcome outcome;
  final DateTime reviewedAt;
  final ReviewPreview preview;
  final dynamic opaqueUndoState;

  const ReviewEventReceipt({
    required this.eventId,
    required this.source,
    required this.schedulingKey,
    required this.outcome,
    required this.reviewedAt,
    required this.preview,
    this.opaqueUndoState,
  });

  @override
  String toString() =>
      'ReviewEventReceipt(id: $eventId, outcome: $outcome, at: $reviewedAt)';
}

/// Due summary returned from the authoritative ledger.
class ReviewDueSummary {
  final int dueCount;
  final int newCount;
  final int learningCount;
  final int reviewCount;
  final bool isUnavailable;

  const ReviewDueSummary({
    required this.dueCount,
    this.newCount = 0,
    this.learningCount = 0,
    this.reviewCount = 0,
    this.isUnavailable = false,
  });

  static const empty = ReviewDueSummary(dueCount: 0);
  static const unavailable = ReviewDueSummary(
    dueCount: 0,
    isUnavailable: true,
  );
}

/// Abstract contract for scheduling ledgers.
///
/// Implementations:
/// - [TurnaReviewLedger]: Manages Turna course words and legacy Anki imports via FSRS.
/// - [OfficialAnkiReviewLedger]: Manages official Anki cards via official scheduler.
abstract interface class ReviewLedger {
  /// Query due statistics for the given scope (deckId, sectionId, etc).
  Future<ReviewDueSummary> dueSummary({String? scope});

  /// Authoritative preview of the next interval for a given outcome.
  Future<ReviewPreview> preview(
    ReviewSchedulingKey key,
    RecallOutcome outcome,
  );

  /// Answer the card and commit the schedule change. Returns a unique receipt.
  Future<ReviewEventReceipt> answer(
    ReviewSchedulingKey key,
    RecallOutcome outcome, {
    int durationMs = 0,
  });

  /// Undo the review represented by the receipt.
  Future<bool> undo(ReviewEventReceipt receipt);
}
