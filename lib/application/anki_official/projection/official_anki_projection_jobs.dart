import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

enum OfficialAnkiProjectionJobState {
  created,
  scanningSource,
  scanningSchema,
  needsMapping,
  projecting,
  publishing,
  active,
  cancelRequested,
  cancelled,
  retryWait,
  failed,
  abandoned,
}

const officialAnkiNonTerminalJobStates = <String>{
  'created',
  'scanning_source',
  'scanning_schema',
  'needs_mapping',
  'projecting',
  'publishing',
  'retry_wait',
  'cancel_requested',
};

class OfficialAnkiProjectionJob {
  const OfficialAnkiProjectionJob({
    required this.jobId,
    required this.sourceId,
    required this.state,
    required this.ownerToken,
    required this.projectionVersion,
    required this.algorithmVersion,
    required this.sourceFingerprint,
    required this.cardSetFingerprint,
    required this.schemaFingerprint,
    required this.mappingFingerprint,
    required this.cursorCardId,
    required this.processedCards,
    required this.totalCards,
    required this.retryCount,
    required this.cancelRequested,
    required this.startedAtMillis,
    required this.heartbeatAtMillis,
    this.completedAtMillis,
    this.lastErrorCode,
  });

  final String jobId;
  final String sourceId;
  final OfficialAnkiProjectionJobState state;
  final String ownerToken;
  final int projectionVersion;
  final int algorithmVersion;
  final String sourceFingerprint;
  final String cardSetFingerprint;
  final String schemaFingerprint;
  final String mappingFingerprint;
  final int? cursorCardId;
  final int processedCards;
  final int totalCards;
  final int retryCount;
  final bool cancelRequested;
  final int startedAtMillis;
  final int heartbeatAtMillis;
  final int? completedAtMillis;
  final String? lastErrorCode;

  bool get isTerminal =>
      state == OfficialAnkiProjectionJobState.cancelled ||
      state == OfficialAnkiProjectionJobState.failed ||
      state == OfficialAnkiProjectionJobState.active ||
      state == OfficialAnkiProjectionJobState.abandoned;

  bool get isResumable =>
      state == OfficialAnkiProjectionJobState.needsMapping ||
      state == OfficialAnkiProjectionJobState.retryWait;
}

class OfficialAnkiProjectionJobRepository {
  OfficialAnkiProjectionJobRepository(this._database);

  final OfficialAnkiDatabase _database;
  Database get _db => _database.handle;

  OfficialAnkiProjectionJob? activeWriter(String sourceId) {
    final rows = _db.select(
      "SELECT * FROM anki_projection_jobs WHERE source_id = ? AND state IN "
      "('created','scanning_source','scanning_schema','needs_mapping',"
      "'projecting','publishing','retry_wait','cancel_requested') "
      'ORDER BY heartbeat_at_millis DESC LIMIT 1',
      [sourceId],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  List<OfficialAnkiProjectionJob> nonTerminalFor(String sourceId) {
    final rows = _db.select(
      "SELECT * FROM anki_projection_jobs WHERE source_id = ? AND state IN "
      "('created','scanning_source','scanning_schema','needs_mapping',"
      "'projecting','publishing','retry_wait','cancel_requested') "
      'ORDER BY started_at_millis ASC',
      [sourceId],
    );
    return [for (final row in rows) _fromRow(row)];
  }

  OfficialAnkiProjectionJob createJob({
    required String jobId,
    required String sourceId,
    required String ownerToken,
    required int nowMillis,
    int projectionVersion = 1,
    int algorithmVersion = officialAnkiProjectionAlgorithmVersion,
  }) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final existing = activeWriter(sourceId);
      if (existing != null) {
        final stale = nowMillis - existing.heartbeatAtMillis >
            officialAnkiProjectionStaleHeartbeatMillis;
        if (!stale) {
          _db.execute('ROLLBACK');
          throw const OfficialAnkiException(
            code: OfficialAnkiErrorCode.invalidState,
            messageKey: 'official_anki.projection_writer_busy',
          );
        }
        _setState(
          existing.jobId,
          OfficialAnkiProjectionJobState.abandoned,
          nowMillis: nowMillis,
          ownerToken: existing.ownerToken,
          errorCode: 'stale_heartbeat',
          completed: true,
        );
      }
      _db.execute(
        'INSERT INTO anki_projection_jobs ('
        'job_id, source_id, state, projection_version, source_fingerprint, '
        'cursor_card_id, processed_cards, total_cards, started_at_millis, '
        'heartbeat_at_millis, completed_at_millis, last_error_code, owner_token, '
        'algorithm_version, retry_count, cancel_requested, card_set_fingerprint, '
        'schema_fingerprint, mapping_fingerprint, last_error_safe_message'
        ') VALUES (?, ?, ?, ?, ?, NULL, 0, 0, ?, ?, NULL, NULL, ?, ?, 0, 0, '
        "'', '', '', NULL)",
        [
          jobId,
          sourceId,
          _sqlState(OfficialAnkiProjectionJobState.created),
          projectionVersion,
          '',
          nowMillis,
          nowMillis,
          ownerToken,
          algorithmVersion,
        ],
      );
      _db.execute('COMMIT');
    } catch (error) {
      try {
        _db.execute('ROLLBACK');
      } catch (_) {}
      if (error is OfficialAnkiException) rethrow;
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.projection_writer_busy',
      );
    }
    return find(jobId)!;
  }

  OfficialAnkiProjectionJob resumeJob({
    required String jobId,
    required String ownerToken,
    required int nowMillis,
  }) {
    final current = find(jobId);
    if (current == null || !current.isResumable) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.projection_job_not_resumable',
      );
    }
    if (current.ownerToken != ownerToken) {
      // Waiting jobs (needs_mapping / retry_wait) are user-held, not an
      // in-flight writer. Adopt so a recreated source page can Generate.
      _db.execute(
        'UPDATE anki_projection_jobs SET owner_token = ?, '
        'heartbeat_at_millis = ? WHERE job_id = ?',
        [ownerToken, nowMillis, jobId],
      );
    }
    heartbeat(
      jobId: jobId,
      ownerToken: ownerToken,
      nowMillis: nowMillis,
      state: OfficialAnkiProjectionJobState.scanningSource,
    );
    return find(jobId)!;
  }

  OfficialAnkiProjectionJob claimStaleJob({
    required String sourceId,
    required String ownerToken,
    required int nowMillis,
    required String newJobId,
  }) {
    final existing = activeWriter(sourceId);
    if (existing == null) {
      return createJob(
        jobId: newJobId,
        sourceId: sourceId,
        ownerToken: ownerToken,
        nowMillis: nowMillis,
      );
    }
    final stale = nowMillis - existing.heartbeatAtMillis >
        officialAnkiProjectionStaleHeartbeatMillis;
    if (!stale) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.projection_writer_busy',
      );
    }
    return createJob(
      jobId: newJobId,
      sourceId: sourceId,
      ownerToken: ownerToken,
      nowMillis: nowMillis,
    );
  }

  OfficialAnkiProjectionJob? find(String jobId) {
    final rows = _db.select(
      'SELECT * FROM anki_projection_jobs WHERE job_id = ?',
      [jobId],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  void heartbeat({
    required String jobId,
    required String ownerToken,
    required int nowMillis,
    OfficialAnkiProjectionJobState? state,
    int? cursorCardId,
    int? processedCards,
    int? totalCards,
    String? sourceFingerprint,
    String? cardSetFingerprint,
    String? schemaFingerprint,
    String? mappingFingerprint,
    String? errorCode,
  }) {
    final current = find(jobId);
    if (current == null || current.ownerToken != ownerToken) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.projection_job_owner_mismatch',
      );
    }
    if (current.cancelRequested &&
        state != OfficialAnkiProjectionJobState.cancelled) {
      state = OfficialAnkiProjectionJobState.cancelRequested;
    }
    _db.execute(
      'UPDATE anki_projection_jobs SET '
      'state = COALESCE(?, state), '
      'heartbeat_at_millis = ?, '
      'cursor_card_id = COALESCE(?, cursor_card_id), '
      'processed_cards = COALESCE(?, processed_cards), '
      'total_cards = COALESCE(?, total_cards), '
      'source_fingerprint = COALESCE(?, source_fingerprint), '
      'card_set_fingerprint = COALESCE(?, card_set_fingerprint), '
      'schema_fingerprint = COALESCE(?, schema_fingerprint), '
      'mapping_fingerprint = COALESCE(?, mapping_fingerprint), '
      'last_error_code = COALESCE(?, last_error_code) '
      'WHERE job_id = ? AND owner_token = ?',
      [
        state == null ? null : _sqlState(state),
        nowMillis,
        cursorCardId,
        processedCards,
        totalCards,
        sourceFingerprint,
        cardSetFingerprint,
        schemaFingerprint,
        mappingFingerprint,
        errorCode,
        jobId,
        ownerToken,
      ],
    );
  }

  bool requestCancel({
    required String jobId,
    required String ownerToken,
    required int nowMillis,
  }) {
    final current = find(jobId);
    if (current == null || current.ownerToken != ownerToken) {
      return false;
    }
    if (current.isTerminal) return false;
    _db.execute(
      'UPDATE anki_projection_jobs SET cancel_requested = 1, '
      "state = 'cancel_requested', heartbeat_at_millis = ? "
      'WHERE job_id = ? AND owner_token = ?',
      [nowMillis, jobId, ownerToken],
    );
    return true;
  }

  void markCancelled({
    required String jobId,
    required String ownerToken,
    required int nowMillis,
  }) {
    _setState(
      jobId,
      OfficialAnkiProjectionJobState.cancelled,
      nowMillis: nowMillis,
      ownerToken: ownerToken,
      completed: true,
    );
  }

  void markAbandoned({
    required String jobId,
    required String ownerToken,
    required int nowMillis,
    String errorCode = 'abandoned',
  }) {
    _setState(
      jobId,
      OfficialAnkiProjectionJobState.abandoned,
      nowMillis: nowMillis,
      ownerToken: ownerToken,
      errorCode: errorCode,
      completed: true,
    );
  }

  void markFailed({
    required String jobId,
    required String ownerToken,
    required int nowMillis,
    required String errorCode,
    bool retryable = false,
  }) {
    _setState(
      jobId,
      retryable
          ? OfficialAnkiProjectionJobState.retryWait
          : OfficialAnkiProjectionJobState.failed,
      nowMillis: nowMillis,
      ownerToken: ownerToken,
      errorCode: errorCode,
      completed: !retryable,
    );
    if (retryable) {
      _db.execute(
        'UPDATE anki_projection_jobs SET retry_count = retry_count + 1 '
        'WHERE job_id = ?',
        [jobId],
      );
    }
  }

  void markActive({
    required String jobId,
    required String ownerToken,
    required int nowMillis,
    required String sourceFingerprint,
  }) {
    _setState(
      jobId,
      OfficialAnkiProjectionJobState.active,
      nowMillis: nowMillis,
      ownerToken: ownerToken,
      completed: true,
    );
    _db.execute(
      'UPDATE anki_projection_jobs SET source_fingerprint = ? WHERE job_id = ?',
      [sourceFingerprint, jobId],
    );
  }

  bool isCancelRequested(String jobId) {
    final job = find(jobId);
    return job?.cancelRequested == true;
  }

  OfficialAnkiProjectionJob _fromRow(Row row) {
    return OfficialAnkiProjectionJob(
      jobId: row['job_id'] as String,
      sourceId: row['source_id'] as String,
      state: _fromSql(row['state'] as String? ?? 'created'),
      ownerToken: row['owner_token'] as String? ?? '',
      projectionVersion: (row['projection_version'] as num?)?.toInt() ?? 1,
      algorithmVersion: (row['algorithm_version'] as num?)?.toInt() ?? 1,
      sourceFingerprint: row['source_fingerprint'] as String? ?? '',
      cardSetFingerprint: row['card_set_fingerprint'] as String? ?? '',
      schemaFingerprint: row['schema_fingerprint'] as String? ?? '',
      mappingFingerprint: row['mapping_fingerprint'] as String? ?? '',
      cursorCardId: (row['cursor_card_id'] as num?)?.toInt(),
      processedCards: (row['processed_cards'] as num?)?.toInt() ?? 0,
      totalCards: (row['total_cards'] as num?)?.toInt() ?? 0,
      retryCount: (row['retry_count'] as num?)?.toInt() ?? 0,
      cancelRequested: (row['cancel_requested'] as int? ?? 0) == 1,
      startedAtMillis: (row['started_at_millis'] as num?)?.toInt() ?? 0,
      heartbeatAtMillis: (row['heartbeat_at_millis'] as num?)?.toInt() ?? 0,
      completedAtMillis: (row['completed_at_millis'] as num?)?.toInt(),
      lastErrorCode: row['last_error_code'] as String?,
    );
  }

  void _setState(
    String jobId,
    OfficialAnkiProjectionJobState state, {
    required int nowMillis,
    required String ownerToken,
    String? errorCode,
    bool completed = false,
  }) {
    _db.execute(
      'UPDATE anki_projection_jobs SET state = ?, heartbeat_at_millis = ?, '
      'last_error_code = COALESCE(?, last_error_code), '
      'completed_at_millis = CASE WHEN ? = 1 THEN ? ELSE completed_at_millis END '
      'WHERE job_id = ? AND owner_token = ?',
      [
        _sqlState(state),
        nowMillis,
        errorCode,
        completed ? 1 : 0,
        nowMillis,
        jobId,
        ownerToken,
      ],
    );
  }

  static String _sqlState(OfficialAnkiProjectionJobState state) {
    switch (state) {
      case OfficialAnkiProjectionJobState.scanningSource:
        return 'scanning_source';
      case OfficialAnkiProjectionJobState.scanningSchema:
        return 'scanning_schema';
      case OfficialAnkiProjectionJobState.needsMapping:
        return 'needs_mapping';
      case OfficialAnkiProjectionJobState.cancelRequested:
        return 'cancel_requested';
      case OfficialAnkiProjectionJobState.retryWait:
        return 'retry_wait';
      default:
        return state.name;
    }
  }

  static OfficialAnkiProjectionJobState _fromSql(String raw) {
    switch (raw) {
      case 'scanning_source':
        return OfficialAnkiProjectionJobState.scanningSource;
      case 'scanning_schema':
        return OfficialAnkiProjectionJobState.scanningSchema;
      case 'needs_mapping':
        return OfficialAnkiProjectionJobState.needsMapping;
      case 'cancel_requested':
        return OfficialAnkiProjectionJobState.cancelRequested;
      case 'retry_wait':
        return OfficialAnkiProjectionJobState.retryWait;
      default:
        return OfficialAnkiProjectionJobState.values.firstWhere(
          (value) => value.name == raw,
          orElse: () => OfficialAnkiProjectionJobState.created,
        );
    }
  }
}
