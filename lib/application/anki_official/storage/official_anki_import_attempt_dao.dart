import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

class OfficialAnkiAttemptRow {
  const OfficialAnkiAttemptRow({
    required this.attemptId,
    required this.sourceId,
    required this.requestId,
    required this.state,
    this.phase = '',
    this.stagingPath,
  });

  final String attemptId;
  final String sourceId;
  final String requestId;
  final String state;
  final String phase;
  final String? stagingPath;
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

  /// 该 source 当前未终态的 attempt 行（无则 null）。
  OfficialAnkiAttemptRow? unfinishedBySource(String sourceId) {
    for (final row in unfinished()) {
      if (row.sourceId == sourceId) return row;
    }
    return null;
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

  void transition({
    required String attemptId,
    required String expectedState,
    required String nextState,
    required int nowMillis,
  }) {
    _db.execute(
      '''
UPDATE anki_import_attempts SET
  state = ?,
  heartbeat_at_millis = ?,
  completed_at_millis = CASE WHEN ? IN (
    'completed', 'cancelled', 'failed_before_import',
    'failed_after_import', 'rolled_back', 'needs_reconciliation',
    'preview_ready', 'retired', 'quarantined'
  ) THEN ? ELSE completed_at_millis END
WHERE attempt_id = ? AND state = ?
''',
      [
        nextState,
        nowMillis,
        nextState,
        nowMillis,
        attemptId,
        expectedState,
      ],
    );
    if (_db.updatedRows != 1) {
      throw StateError('attempt $attemptId was not in $expectedState');
    }
  }

  OfficialAnkiAttemptRow _fromRow(Row row) {
    return OfficialAnkiAttemptRow(
      attemptId: row['attempt_id'] as String,
      sourceId: row['source_id'] as String,
      requestId: row['request_id'] as String,
      state: row['state'] as String,
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
