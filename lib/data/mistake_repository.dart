import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:turna/core/logger.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/repositories/i_mistake_repository.dart';

/// SQLite-backed mistake log, scoped by [languageCode].
class MistakeRepository implements IMistakeRepository {
  MistakeRepository(this._db);

  final CourseDatabase _db;

  static const int defaultMaxEntries = 200;

  @override
  Future<List<MistakeEntry>> load(String languageCode) async {
    final code = LanguageCodes.canonicalize(languageCode);
    final rows = await (_db.select(_db.mistakes)
          ..where((t) => t.languageCode.equals(code))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    return [for (final row in rows) _toEntry(row)];
  }

  @override
  Future<Map<String, int>> loadDailyCounts(String languageCode) async {
    final code = LanguageCodes.canonicalize(languageCode);
    final row = await (_db.select(_db.mistakeAggregates)
          ..where((t) => t.languageCode.equals(code)))
        .getSingleOrNull();
    if (row == null) return <String, int>{};
    try {
      final decoded = jsonDecode(row.dailyCountsJson) as Map<String, dynamic>;
      return {
        for (final e in decoded.entries)
          if (e.value is num) e.key: (e.value as num).toInt(),
      };
    } catch (error) {
      logger.w('MistakeRepository: dailyCounts blob undecodable '
          '(${row.dailyCountsJson.length} chars); treating as empty: $error');
      return <String, int>{};
    }
  }

  @override
  Future<int> loadMasteredTotal(String languageCode) async {
    final code = LanguageCodes.canonicalize(languageCode);
    final row = await (_db.select(_db.mistakeAggregates)
          ..where((t) => t.languageCode.equals(code)))
        .getSingleOrNull();
    return row?.masteredTotal ?? 0;
  }

  @override
  Future<void> replaceAll({
    required String languageCode,
    required List<MistakeEntry> entries,
    required Map<String, int> dailyCounts,
    required int masteredTotal,
    int maxEntries = defaultMaxEntries,
  }) async {
    final code = LanguageCodes.canonicalize(languageCode);
    final kept = entries.length > maxEntries
        ? entries.sublist(entries.length - maxEntries)
        : entries;
    await _db.transaction(() async {
      await (_db.delete(_db.mistakes)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await _db.batch((b) {
        for (var i = 0; i < kept.length; i++) {
          b.insert(_db.mistakes, _toCompanion(code, kept[i], i));
        }
      });
      await _writeAggregates(code, dailyCounts, masteredTotal);
    });
  }

  /// Append [entry] as the newest row (FIFO tail) without rewriting the rest
  /// of the table. The hot path (`record`) used to DELETE-all + rebuild up to
  /// [defaultMaxEntries] rows per wrong answer; this writes exactly one row.
  /// The next sort order is read from the current tail inside the same
  /// transaction, so gaps left by deletes never reorder the log.
  /// [evictOldest] drops the head row first when the caller's in-memory cap
  /// is exceeded. Aggregates are refreshed from the caller's cached values as
  /// a single-row upsert.
  @override
  Future<void> insertEntry({
    required String languageCode,
    required MistakeEntry entry,
    required Map<String, int> dailyCounts,
    required int masteredTotal,
    bool evictOldest = false,
  }) async {
    final code = LanguageCodes.canonicalize(languageCode);
    await _db.transaction(() async {
      if (evictOldest) {
        final oldest = await (_db.select(_db.mistakes)
              ..where((t) => t.languageCode.equals(code))
              ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])
              ..limit(1))
            .getSingleOrNull();
        if (oldest != null) {
          await (_db.delete(_db.mistakes)
                ..where((t) =>
                    t.languageCode.equals(code) & t.id.equals(oldest.id)))
              .go();
        }
      }
      final maxOrder = _db.selectOnly(_db.mistakes)
        ..addColumns([_db.mistakes.sortOrder.max()])
        ..where(_db.mistakes.languageCode.equals(code));
      final row = await maxOrder.getSingle();
      final nextOrder = (row.read(_db.mistakes.sortOrder.max()) ?? -1) + 1;
      await _db.into(_db.mistakes).insert(
            _toCompanion(code, entry, nextOrder),
          );
      await _writeAggregates(code, dailyCounts, masteredTotal);
    });
  }

  /// Update one stored entry in place (e.g. a rewriteCount bump) without
  /// touching row order or the rest of the table. Aggregates are refreshed
  /// only when the caller passes new values.
  @override
  Future<void> updateEntry({
    required String languageCode,
    required MistakeEntry entry,
    Map<String, int>? dailyCounts,
    int? masteredTotal,
  }) async {
    final code = LanguageCodes.canonicalize(languageCode);
    // One transaction so a crash can never land between the row update and
    // the aggregates refresh (same pattern as replaceAll/insertEntry).
    await _db.transaction(() async {
      await (_db.update(_db.mistakes)
            ..where(
                (t) => t.languageCode.equals(code) & t.id.equals(entry.id)))
          .write(_toCompanion(code, entry, null));
      if (dailyCounts != null || masteredTotal != null) {
        await _writeAggregates(
          code,
          dailyCounts ?? const {},
          masteredTotal ?? 0,
        );
      }
    });
  }

  /// Delete the given entries in one statement (review-session mastery,
  /// deck-uninstall bookkeeping) plus a single-row aggregates refresh.
  @override
  Future<void> deleteEntriesByIds({
    required String languageCode,
    required Iterable<String> ids,
    Map<String, int>? dailyCounts,
    int? masteredTotal,
  }) async {
    final code = LanguageCodes.canonicalize(languageCode);
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    await _db.transaction(() async {
      await (_db.delete(_db.mistakes)
            ..where((t) => t.languageCode.equals(code) & t.id.isIn(idSet)))
          .go();
      if (dailyCounts != null || masteredTotal != null) {
        await _writeAggregates(
          code,
          dailyCounts ?? const {},
          masteredTotal ?? 0,
        );
      }
    });
  }

  Future<void> _writeAggregates(
    String code,
    Map<String, int> dailyCounts,
    int masteredTotal,
  ) {
    return _db.into(_db.mistakeAggregates).insertOnConflictUpdate(
          MistakeAggregatesCompanion(
            languageCode: Value(code),
            dailyCountsJson: Value(jsonEncode(dailyCounts)),
            masteredTotal: Value(masteredTotal),
          ),
        );
  }

  @override
  Future<void> deleteLanguage(String languageCode) async {
    final code = LanguageCodes.canonicalize(languageCode);
    await _db.transaction(() async {
      await (_db.delete(_db.mistakes)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (_db.delete(_db.mistakeAggregates)
            ..where((t) => t.languageCode.equals(code)))
          .go();
    });
  }

  /// Idempotent prefs → SQLite copy. Returns true when a prefs blob was
  /// consumed (caller should then clear the prefs keys).
  @override
  Future<bool> migrateFromPrefsJson({
    required String languageCode,
    required String logJson,
    required String dailyCountsJson,
    required int masteredTotal,
  }) async {
    final code = LanguageCodes.canonicalize(languageCode);
    final existing = await (_db.select(_db.mistakes)
          ..where((t) => t.languageCode.equals(code))
          ..limit(1))
        .get();
    if (existing.isNotEmpty) return true;

    List<MistakeEntry> entries;
    var logCorrupted = false;
    try {
      final decoded = jsonDecode(logJson) as List<dynamic>;
      entries = [
        for (final item in decoded)
          if (item is Map<String, dynamic>) MistakeEntry.fromJson(item),
      ];
    } catch (error) {
      entries = const [];
      logCorrupted = true;
      logger.w('MistakeRepository: prefs log blob undecodable '
          '(${logJson.length} chars); keeping prefs for retry: $error');
    }
    Map<String, int> counts;
    var countsCorrupted = false;
    try {
      final decoded = jsonDecode(dailyCountsJson) as Map<String, dynamic>;
      counts = {
        for (final e in decoded.entries)
          if (e.value is num) e.key: (e.value as num).toInt(),
      };
    } catch (error) {
      counts = {};
      countsCorrupted = true;
      logger.w('MistakeRepository: prefs dailyCounts blob undecodable; '
          'keeping prefs for retry: $error');
    }
    if (logCorrupted || countsCorrupted) {
      // Fail-safe (plan §6.2): never consume (and clear) prefs we could not
      // fully read. The next launch retries — a DB write error here would
      // also land in this branch via the thrown exception, not a `true`.
      return false;
    }
    if (entries.isEmpty && counts.isEmpty && masteredTotal == 0) {
      // Genuinely empty blobs: consume so the keys get cleaned up once.
      return true;
    }
    await replaceAll(
      languageCode: code,
      entries: entries,
      dailyCounts: counts,
      masteredTotal: masteredTotal,
    );
    return true;
  }

  MistakesCompanion _toCompanion(
    String languageCode,
    MistakeEntry entry,
    int? sortOrder,
  ) {
    return MistakesCompanion.insert(
      id: entry.id,
      languageCode: Value(languageCode),
      lessonId: entry.lessonId,
      stageId: entry.stageId,
      interactionId: entry.interactionId,
      wordId: Value(entry.wordId),
      expressionId: Value(entry.expressionId),
      grammarPointId: Value(entry.grammarPointId),
      interactionSnapshotJson: Value(
        entry.interactionSnapshot == null
            ? null
            : jsonEncode(entry.interactionSnapshot!.toJson()),
      ),
      userAnswer: Value(entry.userAnswer),
      correctAnswer: Value(entry.correctAnswer),
      timestampMs: entry.timestamp.millisecondsSinceEpoch,
      rewriteCount: Value(entry.rewriteCount),
      // Absent for in-place updates so a bump never clobbers the FIFO order.
      sortOrder: sortOrder == null ? const Value.absent() : Value(sortOrder),
    );
  }

  MistakeEntry _toEntry(Mistake row) {
    return MistakeEntry(
      id: row.id,
      lessonId: row.lessonId,
      stageId: row.stageId,
      interactionId: row.interactionId,
      wordId: row.wordId,
      expressionId: row.expressionId,
      grammarPointId: row.grammarPointId,
      interactionSnapshot: _decodeInteraction(row.interactionSnapshotJson),
      userAnswer: row.userAnswer,
      correctAnswer: row.correctAnswer,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row.timestampMs),
      rewriteCount: row.rewriteCount,
    );
  }

  static Interaction? _decodeInteraction(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Interaction.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      logger.w('MistakeRepository: interaction snapshot undecodable '
          '(${raw.length} chars); dropping snapshot: $error');
      return null;
    }
  }
}
