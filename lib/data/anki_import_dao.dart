// Package imports:
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/data/course_database.dart';

/// Data access object for the `anki_imports` table.
/// Provides CRUD operations for Anki import metadata.
@lazySingleton
class AnkiImportDao {
  final CourseDatabase _db;

  AnkiImportDao(this._db);

  /// Insert or update an import record.
  Future<void> upsert(AnkiImportRecord record) async {
    await _db.into(_db.ankiImports).insertOnConflictUpdate(
          AnkiImportsCompanion.insert(
            importId: record.importId,
            sourcePath: record.sourcePath,
            sourceHash: record.sourceHash,
            importedAt: record.importedAt,
            deckCount: Value(record.deckCount),
            noteCount: Value(record.noteCount),
            cardCount: Value(record.cardCount),
            mediaCount: Value(record.mediaCount),
            notetypesJson: Value(record.notetypesJson),
            aiEnhanced: Value(record.aiEnhanced),
            version: Value(record.version),
          ),
        );
  }

  /// Get all import records, ordered by import time (newest first).
  Future<List<AnkiImportRecord>> getAll() async {
    final rows = await (_db.select(_db.ankiImports)
          ..orderBy([(t) => OrderingTerm.desc(t.importedAt)]))
        .get();
    return rows.map(_toRecord).toList();
  }

  /// Get a single import record by id.
  Future<AnkiImportRecord?> getById(String importId) async {
    final row = await (_db.select(_db.ankiImports)
          ..where((t) => t.importId.equals(importId)))
        .getSingleOrNull();
    return row == null ? null : _toRecord(row);
  }

  /// Find an import by source file hash (for incremental update detection).
  Future<AnkiImportRecord?> findByHash(String sourceHash) async {
    final row = await (_db.select(_db.ankiImports)
          ..where((t) => t.sourceHash.equals(sourceHash)))
        .getSingleOrNull();
    return row == null ? null : _toRecord(row);
  }

  /// Delete an import record.
  Future<void> delete(String importId) async {
    await (_db.delete(_db.ankiImports)
          ..where((t) => t.importId.equals(importId)))
        .go();
  }

  /// Mark an import as AI-enhanced.
  Future<void> markAiEnhanced(String importId) async {
    await (_db.update(_db.ankiImports)
          ..where((t) => t.importId.equals(importId)))
        .write(const AnkiImportsCompanion(aiEnhanced: Value(true)));
  }

  AnkiImportRecord _toRecord(AnkiImport row) {
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
    );
  }
}

/// Plain data class for Anki import metadata (decoupled from Drift row).
class AnkiImportRecord {
  final String importId;
  final String sourcePath;
  final String sourceHash;
  final int importedAt;
  final int deckCount;
  final int noteCount;
  final int cardCount;
  final int mediaCount;
  final String notetypesJson;
  final bool aiEnhanced;
  final int version;

  const AnkiImportRecord({
    required this.importId,
    required this.sourcePath,
    required this.sourceHash,
    required this.importedAt,
    this.deckCount = 0,
    this.noteCount = 0,
    this.cardCount = 0,
    this.mediaCount = 0,
    this.notetypesJson = '{}',
    this.aiEnhanced = false,
    this.version = 1,
  });

  DateTime get importedAtDate =>
      DateTime.fromMillisecondsSinceEpoch(importedAt * 1000);
}
