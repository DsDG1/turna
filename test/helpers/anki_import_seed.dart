// Test-only seeding for the `anki_imports` table. Doc 38 P1-C deleted the
// AnkiImportDao write side (upsert/markComplete/markFailed/markAiEnhanced);
// tests that need rows replicate the same SQL here instead of resurrecting
// production writers.

// Project imports:

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
    'imported_scheduling = ?, last_error = ? WHERE import_id = ?',
    [
      r.status,
      r.sourceCardCount,
      r.importedScheduling ? 1 : 0,
      r.lastError,
      r.importId,
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
