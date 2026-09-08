import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:turna/core/logger.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/mistake_entry.dart';

/// SQLite-backed mistake log, scoped by [languageCode].
class MistakeRepository {
  MistakeRepository(this._db);

  final CourseDatabase _db;

  static const int defaultMaxEntries = 200;

  Future<List<MistakeEntry>> load(String languageCode) async {
    final code = LanguageCodes.canonicalize(languageCode);
    final rows = await (_db.select(_db.mistakes)
          ..where((t) => t.languageCode.equals(code))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    return [for (final row in rows) _toEntry(row)];
  }

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
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<int> loadMasteredTotal(String languageCode) async {
    final code = LanguageCodes.canonicalize(languageCode);
    final row = await (_db.select(_db.mistakeAggregates)
          ..where((t) => t.languageCode.equals(code)))
        .getSingleOrNull();
    return row?.masteredTotal ?? 0;
  }

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
      await _db.into(_db.mistakeAggregates).insertOnConflictUpdate(
            MistakeAggregatesCompanion(
              languageCode: Value(code),
              dailyCountsJson: Value(jsonEncode(dailyCounts)),
              masteredTotal: Value(masteredTotal),
            ),
          );
    });
  }

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
    int sortOrder,
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
      sortOrder: Value(sortOrder),
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
    } catch (_) {
      return null;
    }
  }
}
