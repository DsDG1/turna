import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_sqlite.dart';
import 'package:turna/data/course_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class OfficialAnkiMaintenanceLease {
  OfficialAnkiMaintenanceLease(this._database);

  final OfficialAnkiDatabase _database;
  Database get _db => _database.handle;

  bool tryAcquire({
    required String profileId,
    required String ownerToken,
    required String operationKind,
    required int nowMillis,
    int ttlMillis = 60 * 1000,
    String? processId,
  }) {
    final existing = _db.select(
      'SELECT owner_token, expires_at_millis FROM anki_maintenance_leases '
      'WHERE profile_id = ?',
      [profileId],
    );
    if (existing.isNotEmpty) {
      final row = existing.first;
      final expires = (row['expires_at_millis'] as num?)?.toInt() ?? 0;
      final owner = row['owner_token'] as String? ?? '';
      if (expires > nowMillis && owner != ownerToken) {
        return false;
      }
    }
    _db.execute(
      '''
INSERT INTO anki_maintenance_leases (
  profile_id, owner_token, operation_kind, acquired_at_millis,
  heartbeat_at_millis, expires_at_millis, process_id
) VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(profile_id) DO UPDATE SET
  owner_token = excluded.owner_token,
  operation_kind = excluded.operation_kind,
  heartbeat_at_millis = excluded.heartbeat_at_millis,
  expires_at_millis = excluded.expires_at_millis,
  process_id = excluded.process_id
''',
      [
        profileId,
        ownerToken,
        operationKind,
        nowMillis,
        nowMillis,
        nowMillis + ttlMillis,
        processId,
      ],
    );
    return true;
  }

  void release({required String profileId, required String ownerToken}) {
    _db.execute(
      'DELETE FROM anki_maintenance_leases '
      'WHERE profile_id = ? AND owner_token = ?',
      [profileId, ownerToken],
    );
  }
}

class OfficialAnkiMaintenanceJobDao {
  OfficialAnkiMaintenanceJobDao(this._database);

  final OfficialAnkiDatabase _database;
  Database get _db => _database.handle;

  String enqueue({
    required String profileId,
    required OfficialAnkiMaintenanceKind kind,
    String? sourceId,
    required int nowMillis,
  }) {
    final pending = _db.select(
      'SELECT job_id FROM anki_maintenance_jobs '
      'WHERE profile_id = ? AND kind = ? AND state IN (?, ?) '
      'AND IFNULL(source_id, \'\') = IFNULL(?, \'\')',
      [
        profileId,
        kind.wire,
        OfficialAnkiMaintenanceJobState.pending.wire,
        OfficialAnkiMaintenanceJobState.retryWait.wire,
        sourceId,
      ],
    );
    if (pending.isNotEmpty) {
      return pending.first['job_id'] as String;
    }
    final jobId = newOfficialAnkiId('maj');
    _db.execute(
      '''
INSERT INTO anki_maintenance_jobs (
  job_id, profile_id, source_id, kind, state, attempt_count,
  created_at_millis, heartbeat_at_millis
) VALUES (?, ?, ?, ?, ?, 0, ?, ?)
''',
      [
        jobId,
        profileId,
        sourceId,
        kind.wire,
        OfficialAnkiMaintenanceJobState.pending.wire,
        nowMillis,
        nowMillis,
      ],
    );
    return jobId;
  }

  List<Map<String, Object?>> pending({required String profileId}) {
    return _db
        .select(
          'SELECT * FROM anki_maintenance_jobs WHERE profile_id = ? '
          'AND state IN (?, ?) ORDER BY created_at_millis',
          [
            profileId,
            OfficialAnkiMaintenanceJobState.pending.wire,
            OfficialAnkiMaintenanceJobState.retryWait.wire,
          ],
        )
        .map((row) => Map<String, Object?>.from(row))
        .toList();
  }

  List<Map<String, Object?>> recentFailed({
    required String profileId,
    int limit = 20,
  }) {
    return _db
        .select(
          'SELECT * FROM anki_maintenance_jobs WHERE profile_id = ? '
          'AND state = ? ORDER BY heartbeat_at_millis DESC LIMIT ?',
          [
            profileId,
            OfficialAnkiMaintenanceJobState.failed.wire,
            limit,
          ],
        )
        .map((row) => Map<String, Object?>.from(row))
        .toList();
  }

  void markCompleted({
    required String jobId,
    required int nowMillis,
    int? beforeBytes,
    int? afterBytes,
    int? reclaimedBytes,
  }) {
    _db.execute(
      '''
UPDATE anki_maintenance_jobs SET
  state = ?, completed_at_millis = ?, heartbeat_at_millis = ?,
  before_bytes = COALESCE(?, before_bytes),
  after_bytes = COALESCE(?, after_bytes),
  reclaimed_bytes = COALESCE(?, reclaimed_bytes)
WHERE job_id = ?
''',
      [
        OfficialAnkiMaintenanceJobState.completed.wire,
        nowMillis,
        nowMillis,
        beforeBytes,
        afterBytes,
        reclaimedBytes,
        jobId,
      ],
    );
  }

  void markFailed({
    required String jobId,
    required int nowMillis,
    String? errorCode,
    bool retryable = true,
  }) {
    _db.execute(
      '''
UPDATE anki_maintenance_jobs SET
  state = ?, heartbeat_at_millis = ?, last_error_code = ?,
  attempt_count = attempt_count + 1
WHERE job_id = ?
''',
      [
        retryable
            ? OfficialAnkiMaintenanceJobState.retryWait.wire
            : OfficialAnkiMaintenanceJobState.failed.wire,
        nowMillis,
        errorCode,
        jobId,
      ],
    );
  }
}

class OfficialAnkiMaintenanceRunner {
  OfficialAnkiMaintenanceRunner({
    required this.catalog,
    required this.paths,
    this.engine,
    this.course,
    this.forceCompact = false,
  });

  final OfficialAnkiDatabase catalog;
  final OfficialAnkiPaths paths;
  final OfficialAnkiEngine? engine;
  final CourseDatabase? course;

  /// User-initiated optimize ignores the freelist ratio/byte thresholds
  /// (doc 41 §12.4). Automatic jobs still apply them.
  final bool forceCompact;

  static const freelistBytesThreshold = 16 * 1024 * 1024;
  static const freelistRatioThreshold = 0.20;

  /// [leaseOwnerToken] lets a caller that already holds the maintenance
  /// lease (startup recovery) reuse it instead of being rejected by its
  /// own lease. Standalone callers keep the default random token and the
  /// mutual exclusion against concurrent optimize runs is unchanged.
  Future<int> runPending({
    required String profileId,
    String? leaseOwnerToken,
  }) async {
    final jobs = OfficialAnkiMaintenanceJobDao(catalog);
    final lease = OfficialAnkiMaintenanceLease(catalog);
    final token = leaseOwnerToken ?? newOfficialAnkiId('lease');
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!lease.tryAcquire(
      profileId: profileId,
      ownerToken: token,
      operationKind: 'maintenance',
      nowMillis: now,
    )) {
      return 0;
    }
    var completed = 0;
    try {
      for (final row in jobs.pending(profileId: profileId)) {
        final jobId = row['job_id'] as String;
        final kind = OfficialAnkiMaintenanceKind.tryParse(
          row['kind'] as String? ?? '',
        );
        if (kind == null) continue;
        try {
          final result = await _runKind(kind);
          jobs.markCompleted(
            jobId: jobId,
            nowMillis: DateTime.now().millisecondsSinceEpoch,
            beforeBytes: result.beforeBytes,
            afterBytes: result.afterBytes,
            reclaimedBytes: result.reclaimedBytes,
          );
          completed++;
        } catch (error) {
          debugPrint('[OfficialAnkiMaintenance] $kind failed: $error');
          jobs.markFailed(
            jobId: jobId,
            nowMillis: DateTime.now().millisecondsSinceEpoch,
            errorCode: 'maintenance_failed',
          );
        }
      }
    } finally {
      lease.release(profileId: profileId, ownerToken: token);
    }
    return completed;
  }

  Future<OfficialAnkiCompactResult> _runKind(
    OfficialAnkiMaintenanceKind kind,
  ) async {
    switch (kind) {
      case OfficialAnkiMaintenanceKind.mediaGc:
        final engine = this.engine;
        if (engine == null) {
          return const OfficialAnkiCompactResult(
            skippedReason: 'engine_unavailable',
          );
        }
        final gc = await engine.gcUnusedMedia(dryRun: false);
        return OfficialAnkiCompactResult(
          beforeBytes: gc.reclaimedBytes + gc.trashBytes,
          afterBytes: 0,
          elapsedMillis: 0,
        );
      case OfficialAnkiMaintenanceKind.metadataPrune:
        final engine = this.engine;
        if (engine == null) {
          return const OfficialAnkiCompactResult(
            skippedReason: 'engine_unavailable',
          );
        }
        await engine.pruneEmptyMetadata();
        return const OfficialAnkiCompactResult();
      case OfficialAnkiMaintenanceKind.checkpointRelease:
        return const OfficialAnkiCompactResult();
      case OfficialAnkiMaintenanceKind.compactCollection:
        final engine = this.engine;
        if (engine == null) {
          return compactSqliteFile(paths.collectionFile);
        }
        return engine.compactCollection();
      case OfficialAnkiMaintenanceKind.compactCatalog:
        return compactSqliteFile(paths.catalogFile, force: forceCompact);
      case OfficialAnkiMaintenanceKind.compactCourse:
        return compactCourseDatabase(course, force: forceCompact);
    }
  }

  /// VACUUM [CourseDatabase] on the live Drift connection (doc 41 §12.3):
  /// not nested in a transaction, then verify schema version still matches.
  static Future<OfficialAnkiCompactResult> compactCourseDatabase(
    CourseDatabase? db, {
    bool force = false,
  }) async {
    if (db == null) {
      return const OfficialAnkiCompactResult(
        skippedReason: 'course_db_unavailable',
      );
    }
    final page = await _pragmaInt(db, 'PRAGMA page_size');
    final free = await _pragmaInt(db, 'PRAGMA freelist_count');
    final pages = await _pragmaInt(db, 'PRAGMA page_count');
    final freelistBytes = free * page;
    final ratio = pages == 0 ? 0.0 : free / pages;
    final path = await _mainFilePath(db);
    final before = path != null && File(path).existsSync()
        ? File(path).lengthSync()
        : page * pages;
    if (!force &&
        freelistBytes < freelistBytesThreshold &&
        ratio < freelistRatioThreshold) {
      return OfficialAnkiCompactResult(
        beforeBytes: before,
        afterBytes: before,
        freelistBytesBefore: freelistBytes,
        skippedReason: 'below_threshold',
      );
    }
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    await db.customStatement('VACUUM');
    final version = await _pragmaInt(db, 'PRAGMA user_version');
    if (version != CourseDatabase.kSchemaVersion) {
      throw StateError(
        'course.db user_version $version after VACUUM, '
        'expected ${CourseDatabase.kSchemaVersion}',
      );
    }
    final after = path != null && File(path).existsSync()
        ? File(path).lengthSync()
        : page * await _pragmaInt(db, 'PRAGMA page_count');
    final freeAfter = await _pragmaInt(db, 'PRAGMA freelist_count');
    return OfficialAnkiCompactResult(
      beforeBytes: before,
      afterBytes: after,
      freelistBytesBefore: freelistBytes,
      freelistBytesAfter: freeAfter * page,
    );
  }

  static Future<int> _pragmaInt(CourseDatabase db, String sql) async {
    final row = await db.customSelect(sql).getSingle();
    return row.data.values.first as int;
  }

  static Future<String?> _mainFilePath(CourseDatabase db) async {
    final rows = await db.customSelect('PRAGMA database_list').get();
    for (final row in rows) {
      if ((row.data['name'] as String?) == 'main') {
        final file = row.data['file'] as String?;
        if (file != null && file.isNotEmpty) return file;
      }
    }
    return null;
  }

  static OfficialAnkiCompactResult compactSqliteFile(
    File file, {
    bool force = false,
  }) {
    if (!file.existsSync()) {
      return const OfficialAnkiCompactResult(skippedReason: 'missing');
    }
    final before = file.lengthSync();
    ensureOfficialAnkiSqlite();
    final db = sqlite3.open(file.path);
    try {
      final page = db.select('PRAGMA page_size').first.values.first as int;
      final free = db.select('PRAGMA freelist_count').first.values.first as int;
      final pages = db.select('PRAGMA page_count').first.values.first as int;
      final freelistBytes = free * page;
      final ratio = pages == 0 ? 0.0 : free / pages;
      if (!force &&
          freelistBytes < freelistBytesThreshold &&
          ratio < freelistRatioThreshold) {
        return OfficialAnkiCompactResult(
          beforeBytes: before,
          afterBytes: before,
          freelistBytesBefore: freelistBytes,
          skippedReason: 'below_threshold',
        );
      }
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      db.execute('VACUUM');
    } finally {
      db.dispose();
    }
    final after = file.existsSync() ? file.lengthSync() : 0;
    return OfficialAnkiCompactResult(
      beforeBytes: before,
      afterBytes: after,
      freelistBytesAfter: 0,
    );
  }
}
