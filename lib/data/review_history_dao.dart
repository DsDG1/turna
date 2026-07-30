// Package imports:
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/data/course_database.dart';
import 'package:varnamala/domain/course/srs_word.dart';

/// Data access object for the `review_events` table - the per-card review
/// history that powers the memory-curve / retention features.
///
/// Each row is one SM-2 grade (written from [SrsQueueProvider.reviewItem]).
/// Read by [MemoryCurveProvider] to compute retention, forecast, and maturity.
@lazySingleton
class ReviewHistoryDao {
  final CourseDatabase _db;

  ReviewHistoryDao(this._db);

  /// Append a review event.
  Future<void> insertEvent(ReviewEventRecord event) async {
    await _db.into(_db.reviewEvents).insert(_toCompanion(event));
  }

  /// Append many events in one transaction (Anki revlog migration).
  Future<void> insertBatch(Iterable<ReviewEventRecord> events) async {
    await _db.batch((b) {
      for (final e in events) {
        b.insert(_db.reviewEvents, _toCompanion(e));
      }
    });
  }

  /// Full history for one card, oldest first.
  Future<List<ReviewEventRecord>> eventsForCard(String cardId) async {
    final rows = await (_db.select(_db.reviewEvents)
          ..where((t) => t.cardId.equals(cardId))
          ..orderBy([(t) => OrderingTerm.asc(t.reviewedAt)]))
        .get();
    return rows.map(_toRecord).toList();
  }

  /// Most recent [limit] events across all cards (newest first).
  Future<List<ReviewEventRecord>> recentEvents({int limit = 500}) async {
    final rows = await (_db.select(_db.reviewEvents)
          ..orderBy([(t) => OrderingTerm.desc(t.reviewedAt)])
          ..limit(limit))
        .get();
    return rows.map(_toRecord).toList();
  }

  /// Every event, oldest first. Used by [MemoryCurveProvider] to compute the
  /// retention curve (recall rate bucketed by time since previous review).
  Future<List<ReviewEventRecord>> allEvents() async {
    final rows = await (_db.select(_db.reviewEvents)
          ..orderBy([
            (t) => OrderingTerm.asc(t.cardId),
            (t) => OrderingTerm.asc(t.reviewedAt),
          ]))
        .get();
    return rows.map(_toRecord).toList();
  }

  /// Total event count (dashboard / diagnostics).
  Future<int> count() async {
    final count = _db.selectOnly(_db.reviewEvents)
      ..addColumns([_db.reviewEvents.id.count()]);
    final row = await count.getSingle();
    return row.read(_db.reviewEvents.id.count()) ?? 0;
  }

  /// Number of **fail** reviews (quality < 3) for [cardId] on the local
  /// calendar day of [day]. Used by the same-day relearn ladder (ADR 0029).
  Future<int> countFailsOnLocalDay(String cardId, DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;
    final rows = await (_db.select(_db.reviewEvents)
          ..where((t) =>
              t.cardId.equals(cardId) &
              t.reviewedAt.isBiggerOrEqualValue(startMs) &
              t.reviewedAt.isSmallerThanValue(endMs) &
              t.quality.isSmallerThanValue(3)))
        .get();
    return rows.length;
  }

  /// Delete events whose `cardId` starts with [prefix] (Anki deck uninstall).
  Future<void> deleteByCardPrefix(String prefix) async {
    await (_db.delete(_db.reviewEvents)
          ..where((t) => t.cardId.like('$prefix%')))
        .go();
  }

  ReviewEventsCompanion _toCompanion(ReviewEventRecord e) {
    return ReviewEventsCompanion.insert(
      cardId: e.cardId,
      queue: e.queue,
      reviewedAt: e.reviewedAt.millisecondsSinceEpoch,
      quality: e.quality,
      prevIntervalDays: e.prevIntervalDays,
      nextIntervalDays: e.nextIntervalDays,
      prevEase: e.prevEase,
      nextEase: e.nextEase,
      reps: e.reps,
      lapses: e.lapses,
      type: Value(e.type.name),
    );
  }

  ReviewEventRecord _toRecord(ReviewEvent row) {
    return ReviewEventRecord(
      id: row.id,
      cardId: row.cardId,
      queue: row.queue,
      reviewedAt: DateTime.fromMillisecondsSinceEpoch(row.reviewedAt),
      quality: row.quality,
      prevIntervalDays: row.prevIntervalDays,
      nextIntervalDays: row.nextIntervalDays,
      prevEase: row.prevEase,
      nextEase: row.nextEase,
      reps: row.reps,
      lapses: row.lapses,
      type: row.type == 'expression' ? SrsItemType.expression : SrsItemType.word,
    );
  }
}

/// Plain data class for one review event (decoupled from the Drift row).
class ReviewEventRecord {
  final int? id;
  final String cardId;
  final String queue;
  final DateTime reviewedAt;
  final int quality;
  final int prevIntervalDays;
  final int nextIntervalDays;
  final double prevEase;
  final double nextEase;
  final int reps;
  final int lapses;
  final SrsItemType type;

  const ReviewEventRecord({
    this.id,
    required this.cardId,
    required this.queue,
    required this.reviewedAt,
    required this.quality,
    required this.prevIntervalDays,
    required this.nextIntervalDays,
    required this.prevEase,
    required this.nextEase,
    required this.reps,
    required this.lapses,
    this.type = SrsItemType.word,
  });

  /// A recall is successful at SM-2 quality >= 3.
  bool get recalled => quality >= 3;
}
