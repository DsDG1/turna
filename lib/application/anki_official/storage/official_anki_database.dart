import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/storage/official_anki_sqlite.dart';
import 'package:flutter/foundation.dart' show debugPrint;

const int kOfficialAnkiCatalogSchemaVersion = 12;

/// Independent catalog. Must not live in CourseDatabase (downgrade wipes it).
class OfficialAnkiDatabase {
  OfficialAnkiDatabase.memory() : _db = _openMemory() {
    try {
      _migrate();
    } catch (suppressed) {
      debugPrint('[OfficialAnkiDatabase] suppressed error: $suppressed');
      // A failed migration (e.g. future schema version) must not leak the
      // open handle — on Windows that keeps the file locked for the caller.
      _db.dispose();
      rethrow;
    }
  }

  OfficialAnkiDatabase.file(String path) : _db = _openFile(path) {
    try {
      _migrate();
    } catch (suppressed) {
      debugPrint('[OfficialAnkiDatabase] suppressed error: $suppressed');
      _db.dispose();
      rethrow;
    }
  }

  static Database _openMemory() {
    ensureOfficialAnkiSqlite();
    return _configure(sqlite3.openInMemory());
  }

  static Database _openFile(String path) {
    ensureOfficialAnkiSqlite();
    return _configure(sqlite3.open(path));
  }

  /// Doc 38 P4-C: the catalog is a multi-connection database (main isolate
  /// locator + worker isolate + transient readers). Rollback journal with
  /// no busy timeout risks SQLITE_BUSY on concurrent access; WAL plus a
  /// 5s wait makes the cross-isolate readers safe. In-memory databases
  /// ignore journal_mode=WAL, so the pragma is harmless there.
  static Database _configure(Database db) {
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA busy_timeout = 5000');
    return db;
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
      if (version <= 2) {
        _upgradeToV3();
      }
      if (version <= 3) {
        _upgradeToV4();
      }
      if (version <= 4) {
        _upgradeToV5();
      }
      if (version <= 5) {
        _upgradeToV6();
      }
      if (version <= 6) {
        _upgradeToV7();
      }
      if (version <= 7) {
        _upgradeToV8();
      }
      if (version <= 8) {
        _upgradeToV9();
      }
      if (version <= 9) {
        _upgradeToV10();
      }
      if (version <= 10) {
        _upgradeToV11();
      }
      if (version <= 11) {
        _upgradeToV12();
      }
      _db.execute('PRAGMA user_version = $kOfficialAnkiCatalogSchemaVersion');
      _db.execute('COMMIT');
    } catch (suppressed) {
      debugPrint('[OfficialAnkiDatabase] suppressed error: $suppressed');
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

  void _upgradeToV3() {
    _db.execute('''
CREATE TABLE IF NOT EXISTS anki_projection_mappings (
  profile_id TEXT NOT NULL,
  notetype_id INTEGER NOT NULL,
  schema_fingerprint TEXT NOT NULL,
  mapping_json TEXT NOT NULL,
  status TEXT NOT NULL,
  user_confirmed INTEGER NOT NULL,
  mapping_version INTEGER NOT NULL,
  updated_at_millis INTEGER NOT NULL,
  PRIMARY KEY(profile_id, notetype_id)
);
''');
    _db.execute('''
CREATE TABLE IF NOT EXISTS anki_projection_jobs (
  job_id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL REFERENCES anki_sources(source_id),
  state TEXT NOT NULL,
  projection_version INTEGER NOT NULL,
  source_fingerprint TEXT NOT NULL,
  cursor_card_id INTEGER,
  processed_cards INTEGER NOT NULL DEFAULT 0,
  total_cards INTEGER NOT NULL DEFAULT 0,
  started_at_millis INTEGER NOT NULL,
  heartbeat_at_millis INTEGER NOT NULL,
  completed_at_millis INTEGER,
  last_error_code TEXT
);
''');
    _db.execute('''
CREATE TABLE IF NOT EXISTS anki_course_placement_overrides (
  source_id TEXT NOT NULL REFERENCES anki_sources(source_id),
  card_id INTEGER NOT NULL,
  section_key TEXT,
  unit_key TEXT,
  lesson_key TEXT,
  locked INTEGER NOT NULL,
  updated_at_millis INTEGER NOT NULL,
  PRIMARY KEY(source_id, card_id)
);
''');
    _db.execute('''
CREATE TABLE IF NOT EXISTS anki_source_projection_state (
  source_id TEXT PRIMARY KEY REFERENCES anki_sources(source_id),
  state TEXT NOT NULL,
  active_projection_version INTEGER,
  source_fingerprint TEXT,
  projected_card_count INTEGER NOT NULL DEFAULT 0,
  last_projected_at_millis INTEGER,
  active_job_id TEXT
);
''');
  }

  void _upgradeToV4() {
    _db.execute(
      "ALTER TABLE anki_projection_jobs ADD COLUMN owner_token TEXT NOT NULL DEFAULT ''",
    );
    _db.execute(
      'ALTER TABLE anki_projection_jobs ADD COLUMN algorithm_version INTEGER NOT NULL DEFAULT 1',
    );
    _db.execute(
      'ALTER TABLE anki_projection_jobs ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0',
    );
    _db.execute(
      'ALTER TABLE anki_projection_jobs ADD COLUMN cancel_requested INTEGER NOT NULL DEFAULT 0',
    );
    _db.execute(
      "ALTER TABLE anki_projection_jobs ADD COLUMN card_set_fingerprint TEXT NOT NULL DEFAULT ''",
    );
    _db.execute(
      "ALTER TABLE anki_projection_jobs ADD COLUMN schema_fingerprint TEXT NOT NULL DEFAULT ''",
    );
    _db.execute(
      "ALTER TABLE anki_projection_jobs ADD COLUMN mapping_fingerprint TEXT NOT NULL DEFAULT ''",
    );
    _db.execute(
      'ALTER TABLE anki_projection_jobs ADD COLUMN last_error_safe_message TEXT',
    );
  }

  void _upgradeToV5() {
    final rows = _db.select(
      "SELECT job_id, source_id, owner_token, heartbeat_at_millis "
      "FROM anki_projection_jobs WHERE state IN ("
      "'created','scanning_source','scanning_schema','needs_mapping',"
      "'projecting','publishing','retry_wait','cancel_requested'"
      ') ORDER BY source_id, heartbeat_at_millis DESC, started_at_millis DESC',
    );
    final keep = <String>{};
    for (final row in rows) {
      final sourceId = row['source_id'] as String;
      if (keep.add(sourceId)) continue;
      _db.execute(
        "UPDATE anki_projection_jobs SET state = 'abandoned', "
        "last_error_code = 'migration_duplicate_writer', "
        'completed_at_millis = heartbeat_at_millis '
        'WHERE job_id = ?',
        [row['job_id']],
      );
    }
    _db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS anki_projection_one_active_writer '
      'ON anki_projection_jobs(source_id) WHERE state IN ('
      "'created','scanning_source','scanning_schema','needs_mapping',"
      "'projecting','publishing','retry_wait','cancel_requested')",
    );
  }

  void _upgradeToV6() {
    _db.execute('''
CREATE TABLE IF NOT EXISTS legacy_anki_migrations (
  migration_id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  legacy_import_id TEXT NOT NULL,
  official_source_id TEXT REFERENCES anki_sources(source_id),
  state TEXT NOT NULL,
  scheduling_policy TEXT NOT NULL,
  source_hash TEXT,
  backup_id TEXT,
  backup_manifest_hash TEXT,
  legacy_card_count INTEGER NOT NULL DEFAULT 0,
  matched_card_count INTEGER NOT NULL DEFAULT 0,
  unresolved_card_count INTEGER NOT NULL DEFAULT 0,
  cursor_legacy_card_id INTEGER,
  official_mutation_count_at_cutover INTEGER NOT NULL DEFAULT 0,
  started_at_millis INTEGER NOT NULL,
  updated_at_millis INTEGER NOT NULL,
  completed_at_millis INTEGER,
  last_error_code TEXT,
  last_error_safe_message TEXT,
  UNIQUE(profile_id, legacy_import_id)
);
''');
    _db.execute('''
CREATE TABLE IF NOT EXISTS legacy_anki_card_map (
  migration_id TEXT NOT NULL REFERENCES legacy_anki_migrations(migration_id),
  legacy_card_id INTEGER NOT NULL,
  legacy_word_id TEXT NOT NULL,
  legacy_note_id INTEGER,
  note_guid TEXT,
  template_ord INTEGER NOT NULL,
  official_card_id INTEGER,
  match_method TEXT NOT NULL,
  match_state TEXT NOT NULL,
  content_fingerprint TEXT,
  PRIMARY KEY(migration_id, legacy_card_id)
);
''');
    _db.execute(
      'CREATE INDEX IF NOT EXISTS legacy_anki_card_map_migration_idx '
      'ON legacy_anki_card_map(migration_id)',
    );
  }

  void _upgradeToV7() {
    _db.execute('''
CREATE TABLE IF NOT EXISTS anki_scheduler_mutations (
  mutation_id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  card_id INTEGER NOT NULL,
  queue_epoch INTEGER NOT NULL,
  rating TEXT,
  state TEXT NOT NULL,
  created_at_millis INTEGER NOT NULL,
  updated_at_millis INTEGER NOT NULL
);
''');
    _db.execute(
      'CREATE INDEX IF NOT EXISTS anki_scheduler_mutations_card_idx '
      'ON anki_scheduler_mutations(profile_id, card_id, state)',
    );
  }

  void _upgradeToV8() {
    final hasColumn = _db
        .select("SELECT name FROM pragma_table_info('legacy_anki_migrations') WHERE name='recorded_kind'")
        .isNotEmpty;
    if (!hasColumn) {
      _db.execute(
        "ALTER TABLE legacy_anki_migrations ADD COLUMN recorded_kind TEXT",
      );
    }
  }

  /// Doc 34 W3: reconciliation journal for owner/census repairs.
  void _upgradeToV9() {
    _db.execute('''
CREATE TABLE IF NOT EXISTS anki_source_reconciliation_journal (
  operation_id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  source_id TEXT,
  import_id TEXT,
  before_state TEXT NOT NULL,
  evidence_hash TEXT NOT NULL,
  intended_owner TEXT,
  backup_id TEXT,
  current_step TEXT NOT NULL,
  completed_mutations_json TEXT NOT NULL DEFAULT '[]',
  last_error TEXT,
  retry_policy TEXT NOT NULL,
  rollback_policy TEXT NOT NULL,
  after_cardinality INTEGER,
  after_fingerprint TEXT,
  created_at_millis INTEGER NOT NULL,
  updated_at_millis INTEGER NOT NULL
);
''');
    _db.execute(
      'CREATE INDEX IF NOT EXISTS anki_source_reconciliation_journal_profile_idx '
      'ON anki_source_reconciliation_journal(profile_id, updated_at_millis)',
    );
  }

  /// Doc 38 P5: scan fingerprint of the last successful publish — the
  /// no-op short-circuit input. NULL = unknown → one full projection pass.
  void _upgradeToV10() {
    final hasColumn = _db
        .select(
          "SELECT name FROM pragma_table_info('anki_source_projection_state') "
          "WHERE name='scan_fingerprint'",
        )
        .isNotEmpty;
    if (!hasColumn) {
      _db.execute(
        'ALTER TABLE anki_source_projection_state ADD COLUMN scan_fingerprint TEXT',
      );
    }
  }

  /// Doc 41: import saga journal, source metadata, checkpoints, maintenance.
  void _upgradeToV11() {
    void addColumn(String table, String column, String decl) {
      final hasColumn = _db
          .select(
            "SELECT name FROM pragma_table_info('$table') WHERE name='$column'",
          )
          .isNotEmpty;
      if (!hasColumn) {
        _db.execute('ALTER TABLE $table ADD COLUMN $decl');
      }
    }

    addColumn(
      'anki_import_attempts',
      'user_intent',
      "user_intent TEXT NOT NULL DEFAULT 'undecided'",
    );
    addColumn(
      'anki_import_attempts',
      'native_commit_state',
      "native_commit_state TEXT NOT NULL DEFAULT 'unknown'",
    );
    addColumn(
      'anki_import_attempts',
      'pre_import_generation',
      'pre_import_generation INTEGER',
    );
    addColumn(
      'anki_import_attempts',
      'committed_generation',
      'committed_generation INTEGER',
    );
    addColumn(
      'anki_import_attempts',
      'projection_generation',
      'projection_generation TEXT',
    );
    addColumn(
      'anki_import_attempts',
      'cleanup_phase',
      'cleanup_phase TEXT',
    );
    addColumn(
      'anki_source_cards',
      'notetype_id',
      'notetype_id INTEGER',
    );

    _db.execute('''
CREATE TABLE IF NOT EXISTS anki_source_notetypes (
  source_id TEXT NOT NULL REFERENCES anki_sources(source_id) ON DELETE CASCADE,
  notetype_id INTEGER NOT NULL,
  schema_fingerprint TEXT NOT NULL,
  PRIMARY KEY (source_id, notetype_id)
);
''');
    _db.execute('''
CREATE TABLE IF NOT EXISTS anki_source_decks (
  source_id TEXT NOT NULL REFERENCES anki_sources(source_id) ON DELETE CASCADE,
  deck_id INTEGER NOT NULL,
  PRIMARY KEY (source_id, deck_id)
);
''');
    _db.execute('''
CREATE TABLE IF NOT EXISTS anki_checkpoint_files (
  checkpoint_id TEXT PRIMARY KEY,
  attempt_id TEXT NOT NULL UNIQUE,
  source_id TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  state TEXT NOT NULL,
  bytes INTEGER NOT NULL DEFAULT 0,
  pre_import_generation INTEGER,
  sha256 TEXT,
  created_at_millis INTEGER NOT NULL,
  updated_at_millis INTEGER NOT NULL,
  released_at_millis INTEGER,
  last_error_code TEXT
);
''');
    _db.execute('''
CREATE TABLE IF NOT EXISTS anki_maintenance_jobs (
  job_id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  source_id TEXT,
  kind TEXT NOT NULL,
  state TEXT NOT NULL,
  input_generation INTEGER,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  before_bytes INTEGER,
  after_bytes INTEGER,
  reclaimed_bytes INTEGER,
  created_at_millis INTEGER NOT NULL,
  heartbeat_at_millis INTEGER NOT NULL,
  completed_at_millis INTEGER,
  last_error_code TEXT
);
''');
    _db.execute('''
CREATE TABLE IF NOT EXISTS anki_maintenance_leases (
  profile_id TEXT PRIMARY KEY,
  owner_token TEXT NOT NULL,
  operation_kind TEXT NOT NULL,
  acquired_at_millis INTEGER NOT NULL,
  heartbeat_at_millis INTEGER NOT NULL,
  expires_at_millis INTEGER NOT NULL,
  process_id TEXT
);
''');
    _db.execute('''
CREATE TABLE IF NOT EXISTS anki_cleanup_receipts (
  receipt_id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL,
  phase TEXT NOT NULL,
  ownership_json TEXT NOT NULL,
  collection_cards_requested INTEGER NOT NULL DEFAULT 0,
  collection_cards_removed INTEGER NOT NULL DEFAULT 0,
  collection_cards_remaining INTEGER,
  logical_complete INTEGER NOT NULL DEFAULT 0,
  physical_complete INTEGER NOT NULL DEFAULT 0,
  created_at_millis INTEGER NOT NULL,
  updated_at_millis INTEGER NOT NULL
);
''');
    _db.execute(
      'CREATE INDEX IF NOT EXISTS anki_import_attempts_state_intent_idx '
      'ON anki_import_attempts(state, user_intent)',
    );
    _db.execute(
      'CREATE INDEX IF NOT EXISTS anki_maintenance_jobs_profile_state_idx '
      'ON anki_maintenance_jobs(profile_id, state, kind)',
    );
    _db.execute(
      'CREATE INDEX IF NOT EXISTS anki_source_notetypes_notetype_idx '
      'ON anki_source_notetypes(notetype_id)',
    );
    _db.execute(
      'CREATE INDEX IF NOT EXISTS anki_source_decks_deck_idx '
      'ON anki_source_decks(deck_id)',
    );
  }

  /// Doc 42 P1: staging-first attempt ledger (phase + staging directory).
  void _upgradeToV12() {
    void addColumn(String table, String column, String decl) {
      final hasColumn = _db
          .select(
            "SELECT name FROM pragma_table_info('$table') WHERE name='$column'",
          )
          .isNotEmpty;
      if (!hasColumn) {
        _db.execute('ALTER TABLE $table ADD COLUMN $decl');
      }
    }

    addColumn(
      'anki_import_attempts',
      'phase',
      "phase TEXT NOT NULL DEFAULT ''",
    );
    addColumn(
      'anki_import_attempts',
      'staging_path',
      'staging_path TEXT',
    );
  }

  void close() => _db.dispose();
}
