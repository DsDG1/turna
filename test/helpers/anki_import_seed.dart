// Test-only seeding for the `anki_imports` table. Doc 38 P1-C deleted the
// AnkiImportDao write side (upsert/markComplete/markFailed/markAiEnhanced);
// tests that need rows replicate the same SQL here instead of resurrecting
// production writers.

// Project imports:
import 'package:drift/drift.dart' show Variable;
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/course_database.dart';

Future<void> seedAnkiImportRow(CourseDatabase db, AnkiImportRecord r) async {
  await db.customStatement(
    'INSERT OR REPLACE INTO anki_imports '
    '(import_id, source_path, source_hash, imported_at, deck_count, '
    'note_count, card_count, media_count, notetypes_json, ai_enhanced, '
    'version) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      r.importId,
      r.sourcePath,
      r.sourceHash,
      r.importedAt,
      r.deckCount,
      r.noteCount,
      r.cardCount,
      r.mediaCount,
      r.notetypesJson,
      r.aiEnhanced ? 1 : 0,
      r.version,
    ],
  );
  await db.customStatement(
    'UPDATE anki_imports SET status = ?, source_card_count = ?, '
    'stored_card_count = ?, indexed_card_count = ?, imported_scheduling = ?, '
    'last_error = ? WHERE import_id = ?',
    [
      r.status,
      r.sourceCardCount,
      r.storedCardCount,
      r.indexedCardCount,
      r.importedScheduling ? 1 : 0,
      r.lastError,
      r.importId,
    ],
  );
}

/// Mirrors the retired `markComplete`: reconciliation against
/// `anki_cards_meta` followed by the terminal status update.
Future<void> seedAnkiImportComplete(
  CourseDatabase db,
  String importId, {
  required int sourceCardCount,
  required int indexedCardCount,
  required bool importedScheduling,
}) async {
  final stored = await db.customSelect(
    'SELECT COUNT(*) AS c FROM anki_cards_meta WHERE import_id = ?',
    variables: [Variable<String>(importId)],
  ).get();
  final storedCardCount = stored.first.read<int>('c');
  if (sourceCardCount != storedCardCount ||
      sourceCardCount != indexedCardCount) {
    throw StateError(
      'Anki reconciliation failed: source=$sourceCardCount, '
      'stored=$storedCardCount, indexed=$indexedCardCount',
    );
  }
  await db.customStatement(
    "UPDATE anki_imports SET status = 'complete', source_card_count = ?, "
    'stored_card_count = ?, indexed_card_count = ?, imported_scheduling = ?, '
    'last_error = NULL WHERE import_id = ?',
    [
      sourceCardCount,
      storedCardCount,
      indexedCardCount,
      importedScheduling ? 1 : 0,
      importId,
    ],
  );
}

/// Mirrors the retired `markFailed`.
Future<void> seedAnkiImportFailed(
  CourseDatabase db,
  String importId, {
  String? reason,
}) {
  return db.customStatement(
    "UPDATE anki_imports SET status = 'failed', last_error = ? "
    'WHERE import_id = ?',
    [reason, importId],
  );
}
