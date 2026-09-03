import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;

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
    this.userIntent = 'undecided',
    this.nativeCommitState = 'unknown',
    this.phase = '',
    this.stagingPath,
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
  final String userIntent;
  final String nativeCommitState;
  final String phase;
  final String? stagingPath;

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
    String phase = '',
    String? stagingPath,
  }) {
    _db.execute(
      '''
INSERT INTO anki_import_attempts (
  attempt_id, source_id, request_id, state, started_at_millis,
  heartbeat_at_millis, phase, staging_path
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        attemptId,
        sourceId,
        requestId,
        state,
        nowMillis,
        nowMillis,
        phase,
        stagingPath,
      ],
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
          "'failed_after_import', 'rolled_back', 'needs_reconciliation', "
          "'retired', 'quarantined') "
          "AND IFNULL(phase, '') NOT IN "
          "('cancelled', 'completed', 'quarantined')",
        )
        .map(_fromRow)
        .toList();
  }

  void setPhase({
    required String attemptId,
    required String phase,
    required int nowMillis,
    String? stagingPath,
  }) {
    _db.execute(
      'UPDATE anki_import_attempts SET phase = ?, '
      'staging_path = COALESCE(?, staging_path), '
      'heartbeat_at_millis = ? WHERE attempt_id = ?',
      [phase, stagingPath, nowMillis, attemptId],
    );
  }

  void replaceNoteIds({
    required String attemptId,
    required List<int> noteIds,
  }) {
    _db.execute(
      'UPDATE anki_import_attempts SET receipt_note_ids_json = ? '
      'WHERE attempt_id = ?',
      [jsonEncode(noteIds), attemptId],
    );
  }

  List<int> noteIdPage(String attemptId, int offset, int limit) {
    final all = receiptNoteIds(attemptId);
    if (offset >= all.length) return const [];
    final end = (offset + limit < all.length) ? offset + limit : all.length;
    return all.sublist(offset, end);
  }

  int noteIdCount(String attemptId) {
    return receiptNoteIds(attemptId).length;
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
        '(source_id, card_id, note_id, deck_id, note_guid, template_ord, notetype_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
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
            card.notetypeId,
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
    } catch (suppressed) {
      debugPrint('[OfficialAnkiImportAttemptDao] suppressed error: $suppressed');
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
    String? userIntent,
    String? nativeCommitState,
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
  user_intent = COALESCE(?, user_intent),
  native_commit_state = COALESCE(?, native_commit_state),
  completed_at_millis = CASE WHEN ? IN (
    'completed', 'cancelled', 'failed_before_import',
    'failed_after_import', 'rolled_back', 'needs_reconciliation',
    'preview_ready', 'retired', 'quarantined'
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
        userIntent,
        nativeCommitState,
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
      userIntent: row['user_intent'] as String? ?? 'undecided',
      nativeCommitState: row['native_commit_state'] as String? ?? 'unknown',
      phase: row['phase'] as String? ?? '',
      stagingPath: row['staging_path'] as String?,
    );
  }

  void setUserIntent({
    required String attemptId,
    required OfficialAnkiUserIntent intent,
    required int nowMillis,
  }) {
    _db.execute(
      'UPDATE anki_import_attempts SET user_intent = ?, '
      'heartbeat_at_millis = ? WHERE attempt_id = ?',
      [intent.wire, nowMillis, attemptId],
    );
  }

  void setNativeCommitState({
    required String attemptId,
    required OfficialAnkiNativeCommitState state,
    required int nowMillis,
  }) {
    _db.execute(
      'UPDATE anki_import_attempts SET native_commit_state = ?, '
      'heartbeat_at_millis = ? WHERE attempt_id = ?',
      [state.wire, nowMillis, attemptId],
    );
  }

  /// v2 receipt absorb（ADR 0043 D4 / step4.md B2，catalog v13）：note
  /// ids 直接进 attempt 行——不再写 `anki_import_attempt_notes` 侧表。
  /// importPackage 返回后立刻调用，单条 UPDATE 即落账，把 K2 的「无
  /// receipt 窗口」压到最小；重放同值幂等。
  void absorbReceipt({
    required String attemptId,
    required List<int> noteIds,
    required int nowMillis,
    String? scopeJson,
    int? preImportUsn,
  }) {
    _db.execute(
      'UPDATE anki_import_attempts SET receipt_note_ids_json = ?, '
      'receipt_scope_json = COALESCE(?, receipt_scope_json), '
      'pre_import_usn = COALESCE(?, pre_import_usn), '
      'heartbeat_at_millis = ? WHERE attempt_id = ?',
      [jsonEncode(noteIds), scopeJson, preImportUsn, nowMillis, attemptId],
    );
  }

  /// 吸收进 attempt 行的 receipt note ids（K2 重启重建的输入）。
  List<int> receiptNoteIds(String attemptId) {
    final rows = _db.select(
      'SELECT receipt_note_ids_json FROM anki_import_attempts '
      'WHERE attempt_id = ?',
      [attemptId],
    );
    if (rows.isEmpty) return const [];
    final raw = rows.first['receipt_note_ids_json'] as String?;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<num>().map((n) => n.toInt()).toList();
    } catch (_) {
      return const [];
    }
  }
}
