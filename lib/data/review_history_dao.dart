// Package imports:
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/core/performance_trace.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/sql_like.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/domain/repositories/i_review_history_store.dart';
import 'package:turna/domain/review/review_activity.dart';
import 'package:turna/domain/review/review_history.dart';

export 'package:turna/domain/review/review_activity.dart'
    show ActivityGranularity, ActivityBucketRow;
export 'package:turna/domain/review/review_history.dart';

/// Data access object for the `review_events` table - the per-card review
/// history that powers the memory-curve / retention features.
///
/// Each row is one SM-2 grade (written from [SrsQueueProvider.reviewItem]).
/// Read by [MemoryCurveProvider] to compute retention, forecast, and maturity.
@LazySingleton(as: IReviewHistoryStore)
class ReviewHistoryDao implements IReviewHistoryStore {
  final CourseDatabase _db;

  ReviewHistoryDao(this._db);

  /// Local-day bucketing shifts each timestamp by the host's current UTC
  /// offset before truncating to a day. The SQL `'localtime'` modifier is
  /// deliberately avoided: SQLite ≥3.51 rewrote the date/time subsystem and
  /// some 3.51.x builds return NULL for `'localtime'`/`'utc'` modifiers,
  /// which silently emptied every dashboard aggregation on those hosts
  /// (devices bundle sqlite via sqlite3_flutter_libs and will hit the same
  /// family on upgrade). Trade-off: events inside the ±1h DST shift of a
  /// couple of days per year may bucket into the neighbouring day.
  int get _localUtcOffsetMs => DateTime.now().timeZoneOffset.inMilliseconds;

  /// Append a review event.
  @override
  Future<void> insertEvent(ReviewEventRecord event) async {
    await _db.into(_db.reviewEvents).insert(
          _toCompanion(event),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Append many events in one transaction (Anki revlog migration).
  @override
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
  @override
  Future<List<ReviewEventRecord>> eventsForCard(
    String cardId, {
    String? languageCode,
  }) async {
    final query = _db.select(_db.reviewEvents)
      ..where((t) => t.cardId.equals(cardId));
    _whereLanguage(query, languageCode);
    query.orderBy([(t) => OrderingTerm.asc(t.reviewedAt)]);
    final rows = await query.get();
    return rows.map(_toRecord).toList();
  }

  /// Most recent [limit] events across all cards (newest first).
  @override
  Future<List<ReviewEventRecord>> recentEvents({
    int limit = 500,
    String? languageCode,
  }) async {
    final query = _db.select(_db.reviewEvents);
    _whereLanguage(query, languageCode);
    query
      ..orderBy([(t) => OrderingTerm.desc(t.reviewedAt)])
      ..limit(limit);
    final rows = await query.get();
    return rows.map(_toRecord).toList();
  }

  /// Every event, oldest first. Used by [MemoryCurveProvider] to compute the
  /// retention curve (recall rate bucketed by time since previous review).
  ///
  /// **Never call this from the dashboard home** (Plan 3 §14.2): it loads and
  /// sorts the complete history. Use [eventsBetween] /
  /// [dailyActivityBetween] for bounded, aggregation-friendly reads.
  @override
  Future<List<ReviewEventRecord>> allEvents({String? languageCode}) async {
    final query = _db.select(_db.reviewEvents);
    _whereLanguage(query, languageCode);
    query.orderBy([
      (t) => OrderingTerm.asc(t.cardId),
      (t) => OrderingTerm.asc(t.reviewedAt),
    ]);
    final rows = await query.get();
    return rows.map(_toRecord).toList();
  }

  /// Events with `from <= reviewedAt < to` — a bounded window (e.g. today)
  /// instead of the full history. Ordered chronologically.
  @override
  Future<List<ReviewEventRecord>> eventsBetween(
    DateTime from,
    DateTime to, {
    String? languageCode,
  }) async {
    final query = _db.select(_db.reviewEvents)
      ..where((t) =>
          t.reviewedAt.isBiggerOrEqualValue(from.millisecondsSinceEpoch) &
          t.reviewedAt.isSmallerThanValue(to.millisecondsSinceEpoch));
    _whereLanguage(query, languageCode);
    query.orderBy([(t) => OrderingTerm.asc(t.reviewedAt)]);
    final rows = await query.get();
    return rows.map(_toRecord).toList();
  }

  /// Review counts grouped by **local calendar day** for `from <= day < to`
  /// — the dashboard's 7-day chart query. Returns one row per active day
  /// (days with no reviews are absent; callers fill the gaps), so the result
  /// is bounded by the number of days, not the number of events.
  @override
  Future<List<DailyActivityRow>> dailyActivityBetween(
    DateTime from,
    DateTime to, {
    String? languageCode,
  }) async {
    final lang =
        languageCode == null ? null : LanguageCodes.canonicalize(languageCode);
    final rows = await _db.customSelect(
      'SELECT date((reviewed_at + ?) / 1000, \'unixepoch\') AS day,'
      ' COUNT(*) AS reviewed '
      'FROM review_events '
      'WHERE reviewed_at >= ? AND reviewed_at < ? '
      '${lang == null ? '' : 'AND language_code = ? '}'
      'GROUP BY day ORDER BY day ASC',
      variables: [
        Variable<int>(_localUtcOffsetMs),
        Variable<int>(from.millisecondsSinceEpoch),
        Variable<int>(to.millisecondsSinceEpoch),
        if (lang != null) Variable<String>(lang),
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
  @override
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
      "SELECT strftime('$format', (reviewed_at + ?) / 1000, 'unixepoch') "
      'AS bucket, COUNT(*) AS reviewed '
      'FROM review_events WHERE ${predicates.join(' AND ')} '
      'GROUP BY bucket ORDER BY bucket ASC',
      variables: [Variable<int>(_localUtcOffsetMs), ...variables],
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
  @override
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
    if (filter.sourceKinds != null && filter.sourceKinds!.isNotEmpty) {
      final names = filter.sourceKinds!.map((k) => k.name).toList();
      predicates.add(
        'source_kind IN (${List.filled(names.length, '?').join(', ')})',
      );
      variables.addAll(names.map(Variable.withString));
    } else if (filter.sourceKind != null) {
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
    if (filter.languageCode != null) {
      predicates.add('language_code = ?');
      variables.add(
        Variable.withString(LanguageCodes.canonicalize(filter.languageCode!)),
      );
    }
  }

  /// Review totals per persisted logical source. Card ids are opaque here.
  @override
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
  @override
  Future<int> count({String? languageCode}) async {
    final count = _db.selectOnly(_db.reviewEvents)
      ..addColumns([_db.reviewEvents.id.count()]);
    if (languageCode != null) {
      count.where(
        _db.reviewEvents.languageCode
            .equals(LanguageCodes.canonicalize(languageCode)),
      );
    }
    final row = await count.getSingle();
    return row.read(_db.reviewEvents.id.count()) ?? 0;
  }

  /// Number of **fail** reviews (quality < 3) for [cardId] on the local
  /// calendar day of [day]. Used by the same-day relearn ladder (ADR 0029).
  @override
  Future<int> countFailsOnLocalDay(
    String cardId,
    DateTime day, {
    String? languageCode,
  }) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;
    final query = _db.select(_db.reviewEvents)
      ..where((t) =>
          t.cardId.equals(cardId) &
          t.reviewedAt.isBiggerOrEqualValue(startMs) &
          t.reviewedAt.isSmallerThanValue(endMs) &
          t.quality.isSmallerThanValue(3));
    _whereLanguage(query, languageCode);
    final rows = await query.get();
    return rows.length;
  }

  void _whereLanguage(
    SimpleSelectStatement<$ReviewEventsTable, ReviewEvent> query,
    String? languageCode,
  ) {
    if (languageCode == null) return;
    query.where(
      (t) => t.languageCode.equals(LanguageCodes.canonicalize(languageCode)),
    );
  }

  /// Delete events whose `cardId` starts with [prefix] (Anki deck uninstall).
  /// Wildcards inside [prefix] are escaped, so the match is strictly literal.
  @override
  Future<void> deleteByCardPrefix(String prefix) async {
    await (_db.delete(_db.reviewEvents)
          ..where((t) => prefixLike(t.cardId, prefix)))
        .go();
  }

  /// Remove the newest event for one card. Used by the single-step review
  /// undo action; Anki sessions never allow two pending undos at once.
  /// Pass [languageCode] so an undo can never delete another language's
  /// event when wordIds collide across languages.
  @override
  Future<bool> deleteLatestForCard(String cardId,
      {String? languageCode}) async {
    final query = _db.select(_db.reviewEvents)
      ..where((t) => t.cardId.equals(cardId));
    if (languageCode != null) {
      query.where(
        (t) => t.languageCode.equals(LanguageCodes.canonicalize(languageCode)),
      );
    }
    final row = await (query
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return false;
    await (_db.delete(_db.reviewEvents)..where((t) => t.id.equals(row.id)))
        .go();
    return true;
  }

  /// Remove the exact product review event identified by its ledger receipt.
  @override
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
      languageCode: Value(e.languageCode),
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
      languageCode: row.languageCode,
    );
  }

  static SrsSourceKind _sourceKind(String? value) =>
      SrsSourceKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => SrsSourceKind.course,
      );
}
