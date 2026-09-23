// Package imports:
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/anki/anki_import_record.dart';
import 'package:turna/domain/repositories/i_anki_import_store.dart';

export 'package:turna/domain/anki/anki_import_record.dart';

/// Data access object for the `anki_imports` table.
/// Provides CRUD operations for Anki import metadata.
@LazySingleton(as: IAnkiImportStore)
class AnkiImportDao implements IAnkiImportStore {
  final CourseDatabase _db;

  AnkiImportDao(this._db);

  /// Get all import records, ordered by import time (newest first).
  @override
  Future<List<AnkiImportRecord>> getAll() async {
    final rows = await (_db.select(_db.ankiImports)
          ..orderBy([(t) => OrderingTerm.desc(t.importedAt)]))
        .get();
    if (rows.isEmpty) return const <AnkiImportRecord>[];
    // Fetch lifecycle columns for every import in a single query instead of
    // one _toRecord re-query per row (N+1 -> 2 queries).
    final lifecycleRows = await _db
        .customSelect(
          'SELECT import_id, status, source_card_count, stored_card_count, '
          'indexed_card_count, imported_scheduling, last_error, daily_new_limit, '
          'daily_review_limit FROM anki_imports',
        )
        .get();
    final lifecycleById = <String, QueryRow>{
      for (final r in lifecycleRows) r.read<String>('import_id'): r,
    };
    return [
      for (final row in rows)
        _toRecordWithLifecycle(row, lifecycleById[row.importId]),
    ];
  }

  /// Get a single import record by id.
  @override
  Future<AnkiImportRecord?> getById(String importId) async {
    final row = await (_db.select(_db.ankiImports)
          ..where((t) => t.importId.equals(importId)))
        .getSingleOrNull();
    return row == null ? null : _toRecord(row);
  }

  /// Find an import by source file hash (for incremental update detection).
  @override
  Future<AnkiImportRecord?> findByHash(String sourceHash) async {
    // appendAsNew intentionally permits multiple imports of the same file,
    // so sourceHash is not unique. Use the newest record for preview and
    // incremental-update decisions instead of assuming a single row.
    final rows = await (_db.select(_db.ankiImports)
          ..where((t) => t.sourceHash.equals(sourceHash))
          ..orderBy([
            (t) => OrderingTerm.desc(t.importedAt),
            (t) => OrderingTerm.desc(t.importId),
          ])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : _toRecord(rows.first);
  }

  /// Delete an import record.
  @override
  Future<void> delete(String importId) async {
    await (_db.delete(_db.ankiImports)
          ..where((t) => t.importId.equals(importId)))
        .go();
  }

  @override
  Future<void> setDailyLimits(
    String importId, {
    int? newLimit,
    int? reviewLimit,
  }) async {
    await _db.customStatement(
      'UPDATE anki_imports '
      'SET daily_new_limit = ?, daily_review_limit = ? '
      'WHERE import_id = ?',
      [newLimit, reviewLimit, importId],
    );
  }

  @override
  Future<int?> dailyNewLimitFor(String importId) =>
      _readLimit(importId, 'daily_new_limit');

  @override
  Future<int?> dailyReviewLimitFor(String importId) =>
      _readLimit(importId, 'daily_review_limit');

  Future<int?> _readLimit(String importId, String column) async {
    // [column] is a hardcoded literal ('daily_new_limit' / 'daily_review_limit')
    // from the public callers, so it is safe to interpolate; importId is bound.
    final rows = await _db.customSelect(
      'SELECT $column FROM anki_imports WHERE import_id = ?',
      variables: [Variable.withString(importId)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.read<int?>(column);
  }

  Future<AnkiImportRecord> _toRecord(AnkiImport row) async {
    final lifecycleRows = await _db.customSelect(
      'SELECT status, source_card_count, stored_card_count, '
      'indexed_card_count, imported_scheduling, last_error, daily_new_limit, '
      'daily_review_limit FROM anki_imports WHERE import_id = ?',
      variables: [Variable.withString(row.importId)],
    ).get();
    return _toRecordWithLifecycle(
      row,
      lifecycleRows.isEmpty ? null : lifecycleRows.first,
    );
  }

  /// Build an [AnkiImportRecord] from a typed [AnkiImport] row plus an
  /// already-fetched lifecycle row (null when absent). Shared by [_toRecord]
  /// (single row) and [getAll] (lifecycle fetched once for all imports) so the
  /// list path is not N+1.
  AnkiImportRecord _toRecordWithLifecycle(AnkiImport row, QueryRow? lifecycle) {
    return AnkiImportRecord(
      importId: row.importId,
      sourcePath: row.sourcePath,
      sourceHash: row.sourceHash,
      importedAt: row.importedAt,
      deckCount: row.deckCount,
      noteCount: row.noteCount,
      cardCount: row.cardCount,
      mediaCount: row.mediaCount,
      notetypesJson: row.notetypesJson,
      aiEnhanced: row.aiEnhanced,
      version: row.version,
      dailyNewLimit: lifecycle?.read<int?>('daily_new_limit'),
      dailyReviewLimit: lifecycle?.read<int?>('daily_review_limit'),
      status: lifecycle?.read<String?>('status') ?? 'complete',
      sourceCardCount: lifecycle?.read<int?>('source_card_count') ?? 0,
      importedScheduling:
          (lifecycle?.read<int?>('imported_scheduling') ?? 0) != 0,
      lastError: lifecycle?.read<String?>('last_error'),
    );
  }
}
