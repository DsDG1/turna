// Project imports:
import 'package:turna/domain/review/review_activity.dart';
import 'package:turna/domain/review/review_history.dart';

/// Persistence API for the per-card review event ledger (`review_events`
/// table) that powers the memory-curve / retention features.
///
/// Concrete: `ReviewHistoryDao` in `lib/data`. Application code must depend
/// on this interface only — never on the Drift-backed implementation.
abstract class IReviewHistoryStore {
  /// Append one review event (idempotent by row id).
  Future<void> insertEvent(ReviewEventRecord event);

  /// Append many events in one batch (idempotent by row id).
  Future<void> insertBatch(Iterable<ReviewEventRecord> events);

  /// All events for one card, ascending by review time.
  Future<List<ReviewEventRecord>> eventsForCard(
    String cardId, {
    String? languageCode,
  });

  /// Newest [limit] events, descending by review time.
  Future<List<ReviewEventRecord>> recentEvents({
    int limit = 500,
    String? languageCode,
  });

  /// Every event, ordered by (cardId, reviewedAt).
  Future<List<ReviewEventRecord>> allEvents({String? languageCode});

  /// Events with `reviewedAt` in `[from, to)`.
  Future<List<ReviewEventRecord>> eventsBetween(
    DateTime from,
    DateTime to, {
    String? languageCode,
  });

  /// Per-local-day review counts between [from] and [to].
  Future<List<DailyActivityRow>> dailyActivityBetween(
    DateTime from,
    DateTime to, {
    String? languageCode,
  });

  /// Activity bucketed by [granularity] for the dashboard charts.
  Future<List<ActivityBucketRow>> activityBuckets(
    DateTime from,
    DateTime to,
    ActivityGranularity granularity, {
    ReviewHistoryFilter filter = const ReviewHistoryFilter(),
  });

  /// Recall tally grouped by interval bucket (retention curve).
  Future<List<RetentionBucketRow>> retentionByIntervalBucket(
    DateTime from,
    DateTime to, {
    ReviewHistoryFilter filter = const ReviewHistoryFilter(),
  });

  /// Per-source review counts between [from] and [to].
  Future<Map<String, int>> sourceReviewCounts(
    DateTime from,
    DateTime to, {
    ReviewHistoryFilter filter = const ReviewHistoryFilter(),
  });

  /// Total event count.
  Future<int> count({String? languageCode});

  /// Failed reviews for [cardId] on the local calendar day of [day].
  /// Used by the same-day relearn ladder (ADR 0029).
  Future<int> countFailsOnLocalDay(
    String cardId,
    DateTime day, {
    String? languageCode,
  });

  /// Delete all events whose cardId starts with [prefix] (literal match —
  /// LIKE wildcards are escaped).
  Future<void> deleteByCardPrefix(String prefix);

  /// Remove the newest event for one card (single-step review undo).
  Future<bool> deleteLatestForCard(String cardId, {String? languageCode});

  /// Remove the exact review event identified by its ledger receipt.
  Future<bool> deleteBySourceKey(String sourceKey);
}
