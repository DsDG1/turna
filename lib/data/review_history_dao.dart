// Package imports:
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/diagnostics/performance_trace.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/course/srs_word.dart';

enum ActivityGranularity { day, week, month }

class ActivityBucketRow {
  const ActivityBucketRow({required this.bucket, required this.reviewedCount});
  final String bucket;
  final int reviewedCount;
}

class RetentionBucketRow {
  const RetentionBucketRow({
    required this.intervalBucketDays,
    required this.recalled,
    required this.total,
  });
  final int intervalBucketDays;
  final int recalled;
  final int total;
}

class ReviewHistoryFilter {
  const ReviewHistoryFilter({
    this.sourceKind,
    this.sourceId,
    this.queue,
    this.type,
  });
  final SrsSourceKind? sourceKind;
  final String? sourceId;
  final String? queue;
  final String? type;
}

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
    await _db.into(_db.reviewEvents).insert(
          _toCompanion(event),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Append many events in one transaction (Anki revlog migration).
  Future<void> insertBatch(Iterable<ReviewEventRecord> events) async {
    await _db.batch((b) {
      for (final e in events) {
        b.insert(
          _db.reviewEvents,
          _toCompanion(e),
          mode: InsertMode.insertOrIgnore,
        );
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
  ///
  /// **Never call this from the dashboard home** (Plan 3 §14.2): it loads and
  /// sorts the complete history. Use [eventsBetween] /
  /// [dailyActivityBetween] for bounded, aggregation-friendly reads.
  Future<List<ReviewEventRecord>> allEvents() async {
    final rows = await (_db.select(_db.reviewEvents)
          ..orderBy([
            (t) => OrderingTerm.asc(t.cardId),
            (t) => OrderingTerm.asc(t.reviewedAt),
          ]))
        .get();
    return rows.map(_toRecord).toList();
  }

  /// Events with `from <= reviewedAt < to` — a bounded window (e.g. today)
  /// instead of the full history. Ordered chronologically.
  Future<List<ReviewEventRecord>> eventsBetween(
    DateTime from,
    DateTime to,
  ) async {
    final rows = await (_db.select(_db.reviewEvents)
          ..where((t) =>
              t.reviewedAt.isBiggerOrEqualValue(from.millisecondsSinceEpoch) &
              t.reviewedAt.isSmallerThanValue(to.millisecondsSinceEpoch))
          ..orderBy([(t) => OrderingTerm.asc(t.reviewedAt)]))
        .get();
    return rows.map(_toRecord).toList();
  }

  /// Review counts grouped by **local calendar day** for `from <= day < to`
  /// — the dashboard's 7-day chart query. Returns one row per active day
  /// (days with no reviews are absent; callers fill the gaps), so the result
  /// is bounded by the number of days, not the number of events.
  Future<List<DailyActivityRow>> dailyActivityBetween(
    DateTime from,
    DateTime to,
  ) async {
    final rows = await _db.customSelect(
      'SELECT date(reviewed_at / 1000, \'unixepoch\', \'localtime\') AS day,'
      ' COUNT(*) AS reviewed '
      'FROM review_events '
      'WHERE reviewed_at >= ? AND reviewed_at < ? '
      'GROUP BY day ORDER BY day ASC',
      variables: [
        Variable<int>(from.millisecondsSinceEpoch),
        Variable<int>(to.millisecondsSinceEpoch),
      ],
      readsFrom: {_db.reviewEvents},
    ).get();
    return [
      for (final row in rows)
        DailyActivityRow(
          localDay: _parseLocalDay(row.read<String>('day')),
          reviewedCount: row.read<int>('reviewed'),
        ),
    ];
  }

  /// Fixed-cardinality activity aggregation for insights and the 365-day
  /// heatmap. Returned rows grow with buckets, never with review events.
  Future<List<ActivityBucketRow>> activityBuckets(
    DateTime from,
    DateTime to,
    ActivityGranularity granularity, {
    ReviewHistoryFilter filter = const ReviewHistoryFilter(),
  }) async {
    final trace = Stopwatch()..start();
    final format = switch (granularity) {
      ActivityGranularity.day => '%Y-%m-%d',
      ActivityGranularity.week => '%Y-W%W',
      ActivityGranularity.month => '%Y-%m',
    };
    final predicates = <String>['reviewed_at >= ?', 'reviewed_at < ?'];
    final variables = <Variable<Object>>[
      Variable.withInt(from.millisecondsSinceEpoch),
      Variable.withInt(to.millisecondsSinceEpoch),
    ];
    _appendFilterPredicates(predicates, variables, filter);
    final rows = await _db.customSelect(
      "SELECT strftime('$format', reviewed_at / 1000, 'unixepoch', "
      "'localtime') AS bucket, COUNT(*) AS reviewed "
      'FROM review_events WHERE ${predicates.join(' AND ')} '
      'GROUP BY bucket ORDER BY bucket ASC',
      variables: variables,
      readsFrom: {_db.reviewEvents},
    ).get();
    final result = [
      for (final row in rows)
        ActivityBucketRow(
          bucket: row.read<String>('bucket'),
          reviewedCount: row.read<int>('reviewed'),
        ),
    ];
    trace.stop();
    PerformanceTrace.instance.record(
      feature: 'dao',
      operation: 'query.activityBuckets',
      duration: trace.elapsed,
      resultSize: result.length,
    );
    return result;
  }

  /// SQL-side interval bucketing. Nine rows maximum regardless of history
  /// size; optional filters remain index-friendly prefix/column predicates.
  Future<List<RetentionBucketRow>> retentionByIntervalBucket(
    DateTime from,
    DateTime to, {
    ReviewHistoryFilter filter = const ReviewHistoryFilter(),
  }) async {
    final trace = Stopwatch()..start();
    final predicates = <String>['reviewed_at >= ?', 'reviewed_at < ?'];
    final variables = <Variable<Object>>[
      Variable.withInt(from.millisecondsSinceEpoch),
      Variable.withInt(to.millisecondsSinceEpoch),
    ];
    _appendFilterPredicates(predicates, variables, filter);
    const bucket = 'CASE '
        'WHEN prev_interval_days <= 1 THEN 1 '
        'WHEN prev_interval_days <= 4 THEN 4 '
        'WHEN prev_interval_days <= 7 THEN 7 '
        'WHEN prev_interval_days <= 14 THEN 14 '
        'WHEN prev_interval_days <= 21 THEN 21 '
        'WHEN prev_interval_days <= 30 THEN 30 '
        'WHEN prev_interval_days <= 60 THEN 60 '
        'WHEN prev_interval_days <= 90 THEN 90 ELSE 180 END';
    final rows = await _db.customSelect(
      'SELECT $bucket AS interval_bucket, '
      'SUM(CASE WHEN quality >= 3 THEN 1 ELSE 0 END) AS recalled, '
      'COUNT(*) AS total FROM review_events '
      'WHERE ${predicates.join(' AND ')} '
      'GROUP BY interval_bucket ORDER BY interval_bucket ASC',
      variables: variables,
      readsFrom: {_db.reviewEvents},
    ).get();
    final result = [
      for (final row in rows)
        RetentionBucketRow(
          intervalBucketDays: row.read<int>('interval_bucket'),
          recalled: row.read<int>('recalled'),
          total: row.read<int>('total'),
        ),
    ];
    trace.stop();
    PerformanceTrace.instance.record(
      feature: 'dao',
      operation: 'query.retentionBuckets',
      duration: trace.elapsed,
      resultSize: result.length,
    );
    return result;
  }

  static void _appendFilterPredicates(
    List<String> predicates,
    List<Variable<Object>> variables,
    ReviewHistoryFilter filter,
  ) {
    if (filter.sourceKind != null) {
      predicates.add('source_kind = ?');
      variables.add(Variable.withString(filter.sourceKind!.name));
    }
    if (filter.sourceId != null) {
      predicates.add('source_id = ?');
      variables.add(Variable.withString(filter.sourceId!));
    }
    if (filter.queue != null) {
      predicates.add('queue = ?');
      variables.add(Variable.withString(filter.queue!));
    }
    if (filter.type != null) {
      predicates.add('type = ?');
      variables.add(Variable.withString(filter.type!));
    }
  }

  /// Review totals per persisted logical source. Card ids are opaque here.
  Future<Map<String, int>> sourceReviewCounts(
    DateTime from,
    DateTime to, {
    ReviewHistoryFilter filter = const ReviewHistoryFilter(),
  }) async {
    const source = "CASE source_kind "
        "WHEN 'grammar' THEN 'grammar' "
        "WHEN 'ankiLegacy' THEN 'anki:' || source_id "
        "WHEN 'ankiOfficial' THEN 'official:' || source_id "
        "ELSE 'course' END";
    final predicates = <String>['reviewed_at >= ?', 'reviewed_at < ?'];
    final variables = <Variable<Object>>[
      Variable.withInt(from.millisecondsSinceEpoch),
      Variable.withInt(to.millisecondsSinceEpoch),
    ];
    _appendFilterPredicates(predicates, variables, filter);
    final rows = await _db.customSelect(
      'SELECT $source AS source_id, COUNT(*) AS total FROM review_events '
      'WHERE ${predicates.join(' AND ')} '
      'GROUP BY source_id',
      variables: variables,
      readsFrom: {_db.reviewEvents},
    ).get();
    return {
      for (final row in rows)
        row.read<String>('source_id'): row.read<int>('total'),
    };
  }

  static DateTime _parseLocalDay(String day) {
    final parts = day.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
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

  /// Remove the newest event for one card. Used by the single-step review
  /// undo action; Anki sessions never allow two pending undos at once.
  Future<bool> deleteLatestForCard(String cardId) async {
    final row = await (_db.select(_db.reviewEvents)
          ..where((t) => t.cardId.equals(cardId))
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return false;
    await (_db.delete(_db.reviewEvents)..where((t) => t.id.equals(row.id)))
        .go();
    return true;
  }

  /// Remove the exact product review event identified by its ledger receipt.
  Future<bool> deleteBySourceKey(String sourceKey) async {
    final deleted = await (_db.delete(_db.reviewEvents)
          ..where((table) => table.sourceKey.equals(sourceKey)))
        .go();
    return deleted > 0;
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
      sourceKey: Value(e.sourceKey),
      sourceKind: Value(e.sourceKind.name),
      sourceId: Value(e.sourceId),
      ownerId: Value(e.ownerId),
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
      type:
          row.type == 'expression' ? SrsItemType.expression : SrsItemType.word,
      sourceKey: row.sourceKey,
      sourceKind: _sourceKind(row.sourceKind),
      sourceId: row.sourceId ?? 'course',
      ownerId: row.ownerId,
    );
  }

  static SrsSourceKind _sourceKind(String? value) =>
      SrsSourceKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => SrsSourceKind.course,
      );
}

/// One aggregated day of review activity (dashboard 7-day chart).
class DailyActivityRow {
  final DateTime localDay;
  final int reviewedCount;

  const DailyActivityRow({required this.localDay, required this.reviewedCount});
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
  final String? sourceKey;
  final SrsSourceKind sourceKind;
  final String sourceId;
  final String? ownerId;

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
    this.sourceKey,
    this.sourceKind = SrsSourceKind.course,
    this.sourceId = 'course',
    this.ownerId,
  });

  /// A recall is successful at SM-2 quality >= 3.
  bool get recalled => quality >= 3;
}
