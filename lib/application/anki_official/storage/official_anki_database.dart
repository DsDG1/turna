import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/storage/official_anki_sqlite.dart';

const int kOfficialAnkiCatalogSchemaVersion = 2;

/// Independent catalog. Must not live in CourseDatabase (downgrade wipes it).
class OfficialAnkiDatabase {
  OfficialAnkiDatabase.memory() : _db = _openMemory() {
    _migrate();
  }

  OfficialAnkiDatabase.file(String path) : _db = _openFile(path) {
    _migrate();
  }

  static Database _openMemory() {
    ensureOfficialAnkiSqlite();
    return sqlite3.openInMemory();
  }

  static Database _openFile(String path) {
    ensureOfficialAnkiSqlite();
    return sqlite3.open(path);
  }

  final Database _db;

  Database get handle => _db;

  void _migrate() {
    _db.execute('PRAGMA foreign_keys = ON');
    final row = _db.select('PRAGMA user_version').first;
    final version = row['user_version'] as int? ?? 0;
    if (version > kOfficialAnkiCatalogSchemaVersion) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.catalog_future_version',
      );
    }
    if (version == kOfficialAnkiCatalogSchemaVersion) {
      return;
    }
    _db.execute('BEGIN');
    try {
      if (version == 0) {
        _createV1();
      }
      if (version <= 1) {
        _upgradeToV2();
      }
      _db.execute('PRAGMA user_version = $kOfficialAnkiCatalogSchemaVersion');
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _createV1() {
    _db.execute('''
CREATE TABLE anki_sources (
  source_id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  source_hash TEXT NOT NULL,
  source_size INTEGER NOT NULL,
  display_name TEXT NOT NULL,
  original_uri TEXT,
  state TEXT NOT NULL,
  backend_commit TEXT NOT NULL,
  contract_major INTEGER NOT NULL,
  contract_minor INTEGER NOT NULL,
  import_options_json TEXT NOT NULL,
  active_attempt_id TEXT,
  imported_at_millis INTEGER,
  last_error_code TEXT,
  last_error_safe_message TEXT,
  created_at_millis INTEGER NOT NULL,
  updated_at_millis INTEGER NOT NULL,
  UNIQUE(profile_id, source_hash)
);
''');
    _db.execute('''
CREATE TABLE anki_source_cards (
  source_id TEXT NOT NULL REFERENCES anki_sources(source_id) ON DELETE CASCADE,
  card_id INTEGER NOT NULL,
  note_id INTEGER NOT NULL,
  deck_id INTEGER NOT NULL,
  note_guid TEXT,
  template_ord INTEGER NOT NULL,
  PRIMARY KEY(source_id, card_id)
);
''');
    _db.execute(
      'CREATE INDEX anki_source_cards_card_idx ON anki_source_cards(card_id)',
    );
    _db.execute('''
CREATE TABLE anki_import_attempts (
  attempt_id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL REFERENCES anki_sources(source_id),
  request_id TEXT NOT NULL UNIQUE,
  state TEXT NOT NULL,
  checkpoint_id TEXT,
  native_import_token TEXT,
  imported_note_ids_json TEXT,
  cursor_json TEXT,
  started_at_millis INTEGER NOT NULL,
  heartbeat_at_millis INTEGER NOT NULL,
  completed_at_millis INTEGER,
  last_error_code TEXT,
  recovery_count INTEGER NOT NULL DEFAULT 0
);
''');
  }

  void _upgradeToV2() {
    _db.execute('''
CREATE TABLE IF NOT EXISTS anki_import_attempt_notes (
  attempt_id TEXT NOT NULL REFERENCES anki_import_attempts(attempt_id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL,
  note_id INTEGER NOT NULL,
  PRIMARY KEY(attempt_id, ordinal)
);
''');
    _db.execute(
      'CREATE INDEX IF NOT EXISTS anki_import_attempt_notes_attempt_idx '
      'ON anki_import_attempt_notes(attempt_id)',
    );
    final rows = _db.select(
      'SELECT attempt_id, imported_note_ids_json FROM anki_import_attempts '
      "WHERE imported_note_ids_json IS NOT NULL AND imported_note_ids_json != ''",
    );
    final insert = _db.prepare(
      'INSERT OR IGNORE INTO anki_import_attempt_notes '
      '(attempt_id, ordinal, note_id) VALUES (?, ?, ?)',
    );
    try {
      for (final row in rows) {
        final attemptId = row['attempt_id'] as String;
        final raw = row['imported_note_ids_json'] as String?;
        if (raw == null || raw.isEmpty) continue;
        final decoded = jsonDecode(raw);
        if (decoded is! List) continue;
        for (var i = 0; i < decoded.length; i++) {
          final value = decoded[i];
          if (value is num) {
            insert.execute([attemptId, i, value.toInt()]);
          }
        }
      }
    } finally {
      insert.dispose();
    }
  }

  void close() => _db.dispose();
}
