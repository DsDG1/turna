import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

class OfficialAnkiAttemptRow {
  const OfficialAnkiAttemptRow({
    required this.attemptId,
    required this.sourceId,
    required this.requestId,
    required this.state,
    this.checkpointId,
    this.operationToken,
    this.importedNoteCount = 0,
    this.nextOffset = 0,
    this.cursorJson,
    this.recoveryCount = 0,
  });

  final String attemptId;
  final String sourceId;
  final String requestId;
  final String state;
  final String? checkpointId;
  final String? operationToken;
  final int importedNoteCount;
  final int nextOffset;
  final String? cursorJson;
  final int recoveryCount;

  bool get hasImportedNotes => importedNoteCount > 0;

  @Deprecated('process-local only; not a durable crash token')
  String? get nativeImportToken => operationToken;

  List<int> get importedNoteIds => const <int>[];
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
          "'failed_after_import', 'rolled_back', 'needs_reconciliation')",
        )
        .map(_fromRow)
        .toList();
  }

  void replaceNoteIds({
    required String attemptId,
    required List<int> noteIds,
  }) {
    _db.execute('BEGIN');
    try {
      _db.execute(
        'DELETE FROM anki_import_attempt_notes WHERE attempt_id = ?',
        [attemptId],
      );
      final stmt = _db.prepare(
        'INSERT INTO anki_import_attempt_notes '
        '(attempt_id, ordinal, note_id) VALUES (?, ?, ?)',
      );
      try {
        for (var i = 0; i < noteIds.length; i++) {
          stmt.execute([attemptId, i, noteIds[i]]);
        }
      } finally {
        stmt.dispose();
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<int> noteIdPage(String attemptId, int offset, int limit) {
    return _db
        .select(
          'SELECT note_id FROM anki_import_attempt_notes '
          'WHERE attempt_id = ? ORDER BY ordinal LIMIT ? OFFSET ?',
          [attemptId, limit, offset],
        )
        .map((row) => row['note_id'] as int)
        .toList();
  }

  int noteIdCount(String attemptId) {
    final row = _db.select(
      'SELECT COUNT(*) AS n FROM anki_import_attempt_notes WHERE attempt_id = ?',
      [attemptId],
    ).first;
    return row['n'] as int;
  }

  void commitIndexBatch({
    required String attemptId,
    required String sourceId,
    required List<OfficialAnkiCardDescriptor> cards,
    required int nextOffset,
    required int nowMillis,
  }) {
    _db.execute('BEGIN');
    try {
      final stmt = _db.prepare(
        'INSERT OR REPLACE INTO anki_source_cards '
        '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
        'VALUES (?, ?, ?, ?, ?, ?)',
      );
      try {
        for (final card in cards) {
          stmt.execute([
            sourceId,
            card.cardId,
            card.noteId,
            card.deckId,
            card.noteGuid,
            card.templateOrd,
          ]);
        }
      } finally {
        stmt.dispose();
      }
      _db.execute(
        '''
UPDATE anki_import_attempts SET
  heartbeat_at_millis = ?,
  cursor_json = ?
WHERE attempt_id = ? AND state = 'indexing_cards'
''',
        [nowMillis, jsonEncode({'nextOffset': nextOffset}), attemptId],
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void transition({
    required String attemptId,
    required String expectedState,
    required String nextState,
    required int nowMillis,
    String? checkpointId,
    String? operationToken,
    String? nativeImportToken,
    List<int>? importedNoteIds,
    String? cursorJson,
    String? errorCode,
    bool incrementRecovery = false,
  }) {
    final token = operationToken ?? nativeImportToken;
    if (importedNoteIds != null) {
      replaceNoteIds(attemptId: attemptId, noteIds: importedNoteIds);
    }
    _db.execute(
      '''
UPDATE anki_import_attempts SET
  state = ?,
  heartbeat_at_millis = ?,
  checkpoint_id = COALESCE(?, checkpoint_id),
  native_import_token = COALESCE(?, native_import_token),
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
        token,
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
    final attemptId = row['attempt_id'] as String;
    final cursorRaw = row['cursor_json'] as String?;
    var nextOffset = 0;
    if (cursorRaw != null && cursorRaw.isNotEmpty) {
      final decoded = jsonDecode(cursorRaw);
      if (decoded is Map) {
        nextOffset = (decoded['nextOffset'] as num?)?.toInt() ??
            (decoded['offset'] as num?)?.toInt() ??
            0;
      }
    }
    return OfficialAnkiAttemptRow(
      attemptId: attemptId,
      sourceId: row['source_id'] as String,
      requestId: row['request_id'] as String,
      state: row['state'] as String,
      checkpointId: row['checkpoint_id'] as String?,
      operationToken: row['native_import_token'] as String?,
      importedNoteCount: noteIdCount(attemptId),
      nextOffset: nextOffset,
      cursorJson: cursorRaw,
      recoveryCount: row['recovery_count'] as int? ?? 0,
    );
  }
}
