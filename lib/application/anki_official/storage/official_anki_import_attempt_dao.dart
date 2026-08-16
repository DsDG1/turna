import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

class OfficialAnkiAttemptRow {
  const OfficialAnkiAttemptRow({
    required this.attemptId,
    required this.sourceId,
    required this.requestId,
    required this.state,
    this.checkpointId,
    this.nativeImportToken,
    this.importedNoteIds = const <int>[],
    this.cursorJson,
    this.recoveryCount = 0,
  });

  final String attemptId;
  final String sourceId;
  final String requestId;
  final String state;
  final String? checkpointId;
  final String? nativeImportToken;
  final List<int> importedNoteIds;
  final String? cursorJson;
  final int recoveryCount;
}

class OfficialAnkiImportAttemptDao {
  OfficialAnkiImportAttemptDao(this._database);

  final OfficialAnkiDatabase _database;
  Database get _db => _database.handle;

  void insert({
    required String attemptId,
    required String sourceId,
    required String requestId,
    required String state,
    required int nowMillis,
  }) {
    _db.execute(
      '''
INSERT INTO anki_import_attempts (
  attempt_id, source_id, request_id, state, started_at_millis, heartbeat_at_millis
) VALUES (?, ?, ?, ?, ?, ?)
''',
      [attemptId, sourceId, requestId, state, nowMillis, nowMillis],
    );
  }

  OfficialAnkiAttemptRow? find(String attemptId) {
    final rows = _db.select(
      'SELECT * FROM anki_import_attempts WHERE attempt_id = ?',
      [attemptId],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  List<OfficialAnkiAttemptRow> unfinished() {
    return _db
        .select(
          "SELECT * FROM anki_import_attempts WHERE state NOT IN "
          "('active', 'completed', 'cancelled', 'failed_before_import', "
          "'failed_after_import', 'rolled_back')",
        )
        .map(_fromRow)
        .toList();
  }

  void transition({
    required String attemptId,
    required String expectedState,
    required String nextState,
    required int nowMillis,
    String? checkpointId,
    String? nativeImportToken,
    List<int>? importedNoteIds,
    String? cursorJson,
    String? errorCode,
    bool incrementRecovery = false,
  }) {
    _db.execute(
      '''
UPDATE anki_import_attempts SET
  state = ?,
  heartbeat_at_millis = ?,
  checkpoint_id = COALESCE(?, checkpoint_id),
  native_import_token = COALESCE(?, native_import_token),
  imported_note_ids_json = COALESCE(?, imported_note_ids_json),
  cursor_json = COALESCE(?, cursor_json),
  last_error_code = ?,
  completed_at_millis = CASE WHEN ? IN (
    'completed', 'cancelled', 'failed_before_import',
    'failed_after_import', 'rolled_back', 'needs_reconciliation'
  ) THEN ? ELSE completed_at_millis END,
  recovery_count = recovery_count + ?
WHERE attempt_id = ? AND state = ?
''',
      [
        nextState,
        nowMillis,
        checkpointId,
        nativeImportToken,
        importedNoteIds == null ? null : jsonEncode(importedNoteIds),
        cursorJson,
        errorCode,
        nextState,
        nowMillis,
        incrementRecovery ? 1 : 0,
        attemptId,
        expectedState,
      ],
    );
    if (_db.updatedRows != 1) {
      throw StateError('attempt $attemptId was not in $expectedState');
    }
  }

  OfficialAnkiAttemptRow _fromRow(Row row) {
    final raw = row['imported_note_ids_json'] as String?;
    var ids = const <int>[];
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        ids = decoded.whereType<num>().map((n) => n.toInt()).toList();
      }
    }
    return OfficialAnkiAttemptRow(
      attemptId: row['attempt_id'] as String,
      sourceId: row['source_id'] as String,
      requestId: row['request_id'] as String,
      state: row['state'] as String,
      checkpointId: row['checkpoint_id'] as String?,
      nativeImportToken: row['native_import_token'] as String?,
      importedNoteIds: ids,
      cursorJson: row['cursor_json'] as String?,
      recoveryCount: row['recovery_count'] as int? ?? 0,
    );
  }
}
