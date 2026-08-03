// Package imports:
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/course/srs_word.dart';

/// Data access object for the `srs_states` table - the durable store for
/// [SrsWord] scheduling state (migrated from a prefs JSON blob in schema v7).
///
/// `queue` scopes rows to an owning [SrsQueueProvider] (`'srs'` words/expressions
/// vs `'grammar'`), mirroring the old separate prefs blobs. State is held in
/// memory by the providers for synchronous reads; this DAO backs every
/// write-through (persist / import / remove / clear).
@lazySingleton
class SrsStateDao {
  final CourseDatabase _db;

  SrsStateDao(this._db);

  /// Load every [SrsWord] in [queue] into an id-keyed map. Used by
  /// [SrsQueueProvider.ensureLoaded] at startup to hydrate the in-memory cache.
  Future<Map<String, SrsWord>> loadQueue(String queue) async {
    final rows = await (_db.select(_db.srsStates)
          ..where((t) => t.queue.equals(queue)))
        .get();
    return {for (final r in rows) r.wordId: _toSrsWord(r)};
  }

  /// Insert or update a single [SrsWord] in [queue].
  Future<void> upsert(String queue, SrsWord word) async {
    await _db.into(_db.srsStates).insertOnConflictUpdate(_toCompanion(queue, word));
  }

  /// Insert or update many [SrsWord]s in one transaction (bulk import /
  /// migration backfill).
  Future<void> upsertBatch(String queue, Iterable<SrsWord> words) async {
    await _db.batch((b) {
      for (final w in words) {
        b.insert(_db.srsStates, _toCompanion(queue, w),
            onConflict: DoUpdate((_) => _toCompanion(queue, w)));
      }
    });
  }

  /// Delete a single state row by [wordId].
  Future<void> delete(String wordId) async {
    await (_db.delete(_db.srsStates)..where((t) => t.wordId.equals(wordId))).go();
  }

  /// Delete every row whose `wordId` starts with [prefix] (e.g. uninstalling
  /// an imported Anki deck removes its `anki-<importId>-` entries).
  Future<void> deleteByPrefix(String prefix) async {
    await (_db.delete(_db.srsStates)
          ..where((t) => t.wordId.like('$prefix%')))
        .go();
  }

  /// Delete every row in [queue] (content-update reset).
  Future<void> clearQueue(String queue) async {
    await (_db.delete(_db.srsStates)..where((t) => t.queue.equals(queue))).go();
  }

  /// Most recent [limit] reviewed rows in [queue] (newest first), filtered
  /// to those that have been reviewed at least once. Optional [since]
  /// narrows to rows reviewed on/after the given instant. Used by the
  /// personalized tutor ([SrsTutorProvider]) to assemble context.
  Future<List<SrsWord>> recentReviews({
    String queue = 'srs',
    int limit = 20,
    DateTime? since,
  }) async {
    if (limit <= 0) return const <SrsWord>[];
    final query = _db.select(_db.srsStates)
      ..where((t) => t.queue.equals(queue))
      ..where((t) => t.lastReviewedAt.isNotNull());
    if (since != null) {
      query.where(
        (t) => t.lastReviewedAt.isBiggerOrEqualValue(since.millisecondsSinceEpoch),
      );
    }
    query
      ..orderBy([(t) => OrderingTerm.desc(t.lastReviewedAt)])
      ..limit(limit);
    final rows = await query.get();
    return [for (final r in rows) _toSrsWord(r)];
  }

  SrsStatesCompanion _toCompanion(String queue, SrsWord w) {
    return SrsStatesCompanion.insert(
      wordId: w.wordId,
      queue: queue,
      dueAt: w.dueAt.millisecondsSinceEpoch,
      intervalDays: Value(w.intervalDays),
      ease: Value(w.ease),
      reps: Value(w.reps),
      lapses: Value(w.lapses),
      isLeech: Value(w.isLeech),
      isSuspended: Value(w.isSuspended),
      isBuried: Value(w.isBuried),
      type: Value(w.type.name),
      lastReviewedAt: Value(w.lastReviewedAt?.millisecondsSinceEpoch),
      stability: Value(w.stability),
      difficulty: Value(w.difficulty),
      fsrsState: Value(w.fsrsState),
      learningStep: Value(w.learningStep),
    );
  }

  SrsWord _toSrsWord(SrsState row) {
    return SrsWord(
      wordId: row.wordId,
      dueAt: DateTime.fromMillisecondsSinceEpoch(row.dueAt),
      intervalDays: row.intervalDays,
      ease: row.ease,
      reps: row.reps,
      lapses: row.lapses,
      isLeech: row.isLeech,
      isSuspended: row.isSuspended,
      isBuried: row.isBuried,
      type: _parseType(row.type),
      lastReviewedAt: row.lastReviewedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.lastReviewedAt!),
      stability: row.stability,
      difficulty: row.difficulty,
      fsrsState: row.fsrsState,
      learningStep: row.learningStep,
    );
  }

  SrsItemType _parseType(String name) {
    switch (name) {
      case 'expression':
        return SrsItemType.expression;
      case 'word':
      default:
        return SrsItemType.word;
    }
  }
}
