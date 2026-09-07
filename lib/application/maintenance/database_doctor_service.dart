import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_official/anki_deck_manager.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_pending_imports.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/course_catalog.dart';
import 'package:turna/application/maintenance/storage_inventory_service.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'storage_maintenance_platform_stub.dart'
    if (dart.library.io) 'storage_maintenance_platform_io.dart' as platform;

/// Health inspection report for the primary CourseDatabase (Drift SQLite).
class CourseDbHealthReport {
  const CourseDbHealthReport({
    required this.totalBytes,
    required this.walBytes,
    required this.shmBytes,
    required this.freelistBytes,
    required this.sectionCount,
    required this.unitCount,
    required this.lessonCount,
    required this.wordCount,
    required this.srsCount,
    required this.integrityOk,
    required this.integrityMessage,
    required this.foreignKeyViolations,
  });

  final int totalBytes;
  final int walBytes;
  final int shmBytes;
  final int freelistBytes;
  final int sectionCount;
  final int unitCount;
  final int lessonCount;
  final int wordCount;
  final int srsCount;
  final bool integrityOk;
  final String integrityMessage;
  final int foreignKeyViolations;
}

/// Health inspection report for the Anki official catalog and collection.
class AnkiDbHealthReport {
  const AnkiDbHealthReport({
    required this.isConfigured,
    required this.integrityOk,
    required this.integrityMessage,
    required this.sourceCount,
    required this.pendingCleanupCount,
    required this.quarantinedCount,
    required this.pendingJobsCount,
    required this.failedJobsCount,
    required this.unfinishedImportsCount,
    this.collectionCheckPassed,
  });

  final bool isConfigured;
  final bool integrityOk;
  final String integrityMessage;
  final int sourceCount;
  final int pendingCleanupCount;
  final int quarantinedCount;
  final int pendingJobsCount;
  final int failedJobsCount;
  final int unfinishedImportsCount;
  final bool? collectionCheckPassed;
}

/// Health report for disk artifacts and orphan folders.
class StorageOrphanReport {
  const StorageOrphanReport({
    required this.orphanCount,
    required this.orphanBytes,
    required this.orphans,
  });

  final int orphanCount;
  final int orphanBytes;
  final List<StorageArtifactReport> orphans;
}

/// Comprehensive overall health report across all databases and storage.
class DatabaseDoctorReport {
  const DatabaseDoctorReport({
    required this.courseDb,
    required this.ankiDb,
    required this.storage,
    required this.checkedAt,
  });

  final CourseDbHealthReport courseDb;
  final AnkiDbHealthReport ankiDb;
  final StorageOrphanReport storage;
  final DateTime checkedAt;

  bool get isAllHealthy =>
      courseDb.integrityOk &&
      courseDb.foreignKeyViolations == 0 &&
      ankiDb.integrityOk &&
      ankiDb.failedJobsCount == 0 &&
      ankiDb.quarantinedCount == 0 &&
      ankiDb.pendingCleanupCount == 0 &&
      ankiDb.unfinishedImportsCount == 0 &&
      storage.orphanCount == 0;

  int get totalIssuesCount =>
      (courseDb.integrityOk ? 0 : 1) +
      courseDb.foreignKeyViolations +
      (ankiDb.integrityOk ? 0 : 1) +
      ankiDb.failedJobsCount +
      ankiDb.quarantinedCount +
      ankiDb.pendingCleanupCount +
      ankiDb.unfinishedImportsCount +
      storage.orphanCount;
}

/// Result summary of database optimization.
class DatabaseOptimizationResult {
  const DatabaseOptimizationResult({
    required this.ok,
    this.courseDbBytesBefore = 0,
    this.courseDbBytesAfter = 0,
    this.courseDbReclaimedBytes = 0,
    this.ankiJobsCompleted = 0,
    this.errorCode,
    this.message,
  });

  final bool ok;
  final int courseDbBytesBefore;
  final int courseDbBytesAfter;
  final int courseDbReclaimedBytes;
  final int ankiJobsCompleted;
  final String? errorCode;
  final String? message;
}

/// Unified diagnostic, health inspection, optimization, and repair service.
/// Decouples core app database health from Anki-specific engine mechanics.
class DatabaseDoctorService {
  const DatabaseDoctorService();

  static CourseDatabase? _resolveCourse(CourseDatabase? injected) {
    if (injected != null) return injected;
    if (getIt.isRegistered<CourseDatabase>()) {
      return getIt<CourseDatabase>();
    }
    return null;
  }

  static OfficialAnkiDatabase? _resolveCatalog(OfficialAnkiDatabase? injected) {
    return injected ?? OfficialAnkiCompositionRoot.readOnlyCatalog;
  }

  static OfficialAnkiPaths? _resolvePaths(OfficialAnkiPaths? injected) {
    return injected ?? OfficialAnkiCompositionRoot.locatorPaths;
  }

  static OfficialAnkiEngine? _resolveEngine(OfficialAnkiEngine? injected) {
    return injected ?? OfficialAnkiCompositionRoot.engine;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Inspection & Diagnostics
  // ─────────────────────────────────────────────────────────────────────────

  Future<DatabaseDoctorReport> inspectHealth({
    CourseDatabase? course,
    OfficialAnkiDatabase? catalog,
    OfficialAnkiPaths? paths,
    StorageInventoryService? scanner,
  }) async {
    final resolvedCourse = _resolveCourse(course);
    final resolvedCatalog = _resolveCatalog(catalog);
    final resolvedPaths = _resolvePaths(paths);

    final results = await Future.wait([
      _inspectCourseDb(resolvedCourse),
      _inspectAnkiDb(resolvedCatalog, resolvedPaths),
      _inspectStorage(scanner),
    ]);

    return DatabaseDoctorReport(
      courseDb: results[0] as CourseDbHealthReport,
      ankiDb: results[1] as AnkiDbHealthReport,
      storage: results[2] as StorageOrphanReport,
      checkedAt: DateTime.now(),
    );
  }

  Future<CourseDbHealthReport> _inspectCourseDb(CourseDatabase? db) async {
    if (db == null) {
      return const CourseDbHealthReport(
        totalBytes: 0,
        walBytes: 0,
        shmBytes: 0,
        freelistBytes: 0,
        sectionCount: 0,
        unitCount: 0,
        lessonCount: 0,
        wordCount: 0,
        srsCount: 0,
        integrityOk: false,
        integrityMessage: 'course_database_unregistered',
        foreignKeyViolations: 0,
      );
    }

    var totalBytes = 0;
    var walBytes = 0;
    var shmBytes = 0;
    var freelistBytes = 0;
    final mainFile = await _mainDatabasePath(db);

    try {
      final pageSize = await _pragmaInt(db, 'PRAGMA page_size');
      final pageCount = await _pragmaInt(db, 'PRAGMA page_count');
      final freeCount = await _pragmaInt(db, 'PRAGMA freelist_count');
      freelistBytes = freeCount * pageSize;
      totalBytes = pageSize * pageCount;

      if (mainFile != null && mainFile.isNotEmpty) {
        final realDb = await platform.fileSizeBytes(mainFile);
        if (realDb > 0) totalBytes = realDb;
        walBytes = await platform.fileSizeBytes('$mainFile-wal');
        shmBytes = await platform.fileSizeBytes('$mainFile-shm');
      }
    } catch (_) {}

    // Row counts
    var sectionCount = 0;
    var unitCount = 0;
    var lessonCount = 0;
    var wordCount = 0;
    var srsCount = 0;
    try {
      sectionCount = await _countTable(db, 'sections');
      unitCount = await _countTable(db, 'units');
      lessonCount = await _countTable(db, 'lessons');
      wordCount = await _countTable(db, 'vocabulary');
      srsCount = await _countTable(db, 'srs_states');
    } catch (_) {}

    // PRAGMA integrity_check
    var integrityOk = true;
    var integrityMessage = 'ok';
    try {
      final rows = await db.customSelect('PRAGMA integrity_check').get();
      if (rows.isNotEmpty) {
        integrityMessage = rows.first.data.values.first.toString();
        integrityOk = integrityMessage == 'ok';
      }
    } catch (e) {
      integrityOk = false;
      integrityMessage = e.toString();
    }

    // PRAGMA foreign_key_check
    var foreignKeyViolations = 0;
    try {
      final rows = await db.customSelect('PRAGMA foreign_key_check').get();
      foreignKeyViolations = rows.length;
    } catch (_) {}

    return CourseDbHealthReport(
      totalBytes: totalBytes,
      walBytes: walBytes,
      shmBytes: shmBytes,
      freelistBytes: freelistBytes,
      sectionCount: sectionCount,
      unitCount: unitCount,
      lessonCount: lessonCount,
      wordCount: wordCount,
      srsCount: srsCount,
      integrityOk: integrityOk,
      integrityMessage: integrityMessage,
      foreignKeyViolations: foreignKeyViolations,
    );
  }

  Future<AnkiDbHealthReport> _inspectAnkiDb(
    OfficialAnkiDatabase? catalog,
    OfficialAnkiPaths? paths,
  ) async {
    if (catalog == null) {
      return const AnkiDbHealthReport(
        isConfigured: false,
        integrityOk: true,
        integrityMessage: 'not_configured',
        sourceCount: 0,
        pendingCleanupCount: 0,
        quarantinedCount: 0,
        pendingJobsCount: 0,
        failedJobsCount: 0,
        unfinishedImportsCount: 0,
      );
    }

    final profileId = paths?.profileId ?? CourseCatalog.officialProfileId;
    var integrityOk = true;
    var integrityMessage = 'ok';
    try {
      final row = catalog.handle.select('PRAGMA integrity_check').first;
      integrityMessage = row.values.first.toString();
      integrityOk = integrityMessage == 'ok';
    } catch (e) {
      integrityOk = false;
      integrityMessage = e.toString();
    }

    final sourceDao = OfficialAnkiSourceDao(catalog);
    final sources = sourceDao.listSources(profileId);
    final sourceCount = sources.length;
    final pendingCleanupCount = sources
        .where((s) =>
            s.state == 'pending_cleanup' ||
            s.state == 'retiring')
        .length;
    final quarantinedCount =
        sources.where((s) => s.state == 'quarantined').length;

    final jobDao = OfficialAnkiMaintenanceJobDao(catalog);
    final pendingJobsCount = jobDao.pending(profileId: profileId).length;
    final failedJobsCount = jobDao.recentFailed(profileId: profileId).length;

    final pendingImports =
        const OfficialAnkiPendingImportStore().list(catalog).length;

    return AnkiDbHealthReport(
      isConfigured: true,
      integrityOk: integrityOk,
      integrityMessage: integrityMessage,
      sourceCount: sourceCount,
      pendingCleanupCount: pendingCleanupCount,
      quarantinedCount: quarantinedCount,
      pendingJobsCount: pendingJobsCount,
      failedJobsCount: failedJobsCount,
      unfinishedImportsCount: pendingImports,
    );
  }

  Future<StorageOrphanReport> _inspectStorage(
    StorageInventoryService? scanner,
  ) async {
    try {
      if (scanner == null && !getIt.isRegistered<CourseDatabase>()) {
        return const StorageOrphanReport(
          orphanCount: 0,
          orphanBytes: 0,
          orphans: [],
        );
      }
      final report =
          await (scanner ?? const StorageInventoryService()).scan();
      final orphans = report.orphans;
      final orphanBytes =
          orphans.fold<int>(0, (sum, a) => sum + a.physicalBytes);
      return StorageOrphanReport(
        orphanCount: orphans.length,
        orphanBytes: orphanBytes,
        orphans: orphans,
      );
    } catch (e) {
      debugPrint('[DatabaseDoctorService] storage scan failed: $e');
      return const StorageOrphanReport(
        orphanCount: 0,
        orphanBytes: 0,
        orphans: [],
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Standalone Course Database Optimization (WAL + VACUUM + REINDEX + OPTIMIZE)
  // ─────────────────────────────────────────────────────────────────────────

  Future<DatabaseOptimizationResult> optimizeCourseDb({
    CourseDatabase? course,
    bool force = true,
  }) async {
    final db = _resolveCourse(course);
    if (db == null) {
      return const DatabaseOptimizationResult(
        ok: false,
        errorCode: 'course_db_unavailable',
        message: '核心课程数据库未就绪',
      );
    }

    try {
      final pageSize = await _pragmaInt(db, 'PRAGMA page_size');
      final pageCount = await _pragmaInt(db, 'PRAGMA page_count');
      final mainFile = await _mainDatabasePath(db);
      final beforeBytes = mainFile != null && File(mainFile).existsSync()
          ? File(mainFile).lengthSync()
          : pageSize * pageCount;

      // Checkpoint WAL log
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');

      // Defragment and compact database file
      await db.customStatement('VACUUM');

      // Rebuild indexes for optimized lookup
      await db.customStatement('REINDEX');

      // Run query planner cost optimizer
      await db.customStatement('PRAGMA optimize');

      final afterPageCount = await _pragmaInt(db, 'PRAGMA page_count');
      final afterBytes = mainFile != null && File(mainFile).existsSync()
          ? File(mainFile).lengthSync()
          : pageSize * afterPageCount;

      final reclaimed = beforeBytes > afterBytes ? beforeBytes - afterBytes : 0;

      return DatabaseOptimizationResult(
        ok: true,
        courseDbBytesBefore: beforeBytes,
        courseDbBytesAfter: afterBytes,
        courseDbReclaimedBytes: reclaimed,
      );
    } catch (e) {
      debugPrint('[DatabaseDoctorService] optimizeCourseDb failed: $e');
      return DatabaseOptimizationResult(
        ok: false,
        errorCode: 'optimize_failed',
        message: e.toString(),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Comprehensive Unified Optimization
  // ─────────────────────────────────────────────────────────────────────────

  Future<DatabaseOptimizationResult> optimizeAll({
    CourseDatabase? course,
    OfficialAnkiDatabase? catalog,
    OfficialAnkiPaths? paths,
    OfficialAnkiEngine? engine,
    bool force = true,
  }) async {
    // 1. Always optimize CourseDatabase first
    final courseRes = await optimizeCourseDb(course: course, force: force);

    var ankiCompleted = 0;
    final resolvedCatalog = _resolveCatalog(catalog);
    final resolvedPaths = _resolvePaths(paths);
    var resolvedEngine = _resolveEngine(engine);

    // 2. If Anki catalog & paths are configured, optimize Anki too
    if (resolvedCatalog != null && resolvedPaths != null) {
      if (resolvedEngine == null) {
        try {
          await OfficialAnkiCompositionRoot.requireImporter();
          resolvedEngine = OfficialAnkiCompositionRoot.engine;
        } catch (_) {}
      }

      if (resolvedEngine != null) {
        try {
          final now = DateTime.now().millisecondsSinceEpoch;
          final jobs = OfficialAnkiMaintenanceJobDao(resolvedCatalog);
          final profileId = resolvedPaths.profileId;

          jobs.enqueue(
            profileId: profileId,
            kind: OfficialAnkiMaintenanceKind.mediaGc,
            nowMillis: now,
          );
          jobs.enqueue(
            profileId: profileId,
            kind: OfficialAnkiMaintenanceKind.compactCollection,
            nowMillis: now,
          );
          jobs.enqueue(
            profileId: profileId,
            kind: OfficialAnkiMaintenanceKind.compactCatalog,
            nowMillis: now,
          );

          ankiCompleted = await OfficialAnkiMaintenanceRunner(
            catalog: resolvedCatalog,
            paths: resolvedPaths,
            engine: resolvedEngine,
            course: _resolveCourse(course),
            forceCompact: true,
          ).runPending(profileId: profileId);
        } catch (e) {
          debugPrint('[DatabaseDoctorService] anki maintenance failed: $e');
        }
      }
    }

    return DatabaseOptimizationResult(
      ok: courseRes.ok,
      courseDbBytesBefore: courseRes.courseDbBytesBefore,
      courseDbBytesAfter: courseRes.courseDbBytesAfter,
      courseDbReclaimedBytes: courseRes.courseDbReclaimedBytes,
      ankiJobsCompleted: ankiCompleted,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Repair Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Deletes orphan storage directories.
  Future<int> cleanOrphans({
    List<StorageArtifactReport>? targets,
    StorageInventoryService? scanner,
  }) async {
    if (!getIt.isRegistered<AnkiDeckManager>()) return 0;
    final list = targets ??
        (await (scanner ?? const StorageInventoryService()).scan()).orphans;
    var cleaned = 0;
    for (final orphan in list) {
      try {
        if (await getIt<AnkiDeckManager>().uninstall(orphan.ownerId)) {
          cleaned++;
        }
      } catch (e) {
        debugPrint(
            '[DatabaseDoctorService] orphan clean failed for ${orphan.ownerId}: $e');
      }
    }
    return cleaned;
  }

  /// Retries all failed maintenance jobs.
  Future<int> retryFailedJobs({
    OfficialAnkiDatabase? catalog,
    OfficialAnkiPaths? paths,
    CourseDatabase? course,
    OfficialAnkiEngine? engine,
  }) async {
    final resolvedCatalog = _resolveCatalog(catalog);
    final resolvedPaths = _resolvePaths(paths);
    if (resolvedCatalog == null || resolvedPaths == null) return 0;

    final profileId = resolvedPaths.profileId;
    final jobDao = OfficialAnkiMaintenanceJobDao(resolvedCatalog);
    jobDao.retryAllFailed(
      profileId: profileId,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
    );

    var resolvedEngine = _resolveEngine(engine);
    if (resolvedEngine == null) {
      try {
        await OfficialAnkiCompositionRoot.requireImporter();
        resolvedEngine = OfficialAnkiCompositionRoot.engine;
      } catch (_) {}
    }

    if (resolvedEngine == null) return 0;

    return await OfficialAnkiMaintenanceRunner(
      catalog: resolvedCatalog,
      paths: resolvedPaths,
      engine: resolvedEngine,
      course: _resolveCourse(course),
    ).runPending(profileId: profileId);
  }

  /// Clears failed maintenance jobs from history.
  int clearFailedJobs({
    OfficialAnkiDatabase? catalog,
    OfficialAnkiPaths? paths,
  }) {
    final resolvedCatalog = _resolveCatalog(catalog);
    final resolvedPaths = _resolvePaths(paths);
    if (resolvedCatalog == null || resolvedPaths == null) return 0;

    return OfficialAnkiMaintenanceJobDao(resolvedCatalog)
        .clearFailed(profileId: resolvedPaths.profileId);
  }

  /// Deletes a single job.
  void deleteJob({
    required String jobId,
    OfficialAnkiDatabase? catalog,
  }) {
    final resolvedCatalog = _resolveCatalog(catalog);
    if (resolvedCatalog == null) return;
    OfficialAnkiMaintenanceJobDao(resolvedCatalog).deleteJob(jobId: jobId);
  }

  /// Rebuilds indexes on CourseDatabase.
  Future<void> rebuildCourseIndexes({CourseDatabase? course}) async {
    final db = _resolveCourse(course);
    if (db == null) return;
    await db.customStatement('REINDEX');
    await db.customStatement('PRAGMA optimize');
  }

  /// Runs SQLite PRAGMA integrity_check on CourseDatabase.
  Future<String> checkCourseIntegrity({CourseDatabase? course}) async {
    final db = _resolveCourse(course);
    if (db == null) return 'course_db_unavailable';
    final rows = await db.customSelect('PRAGMA integrity_check').get();
    return rows.map((r) => r.data.values.join(' ')).join('\n');
  }

  /// Runs Anki's native collection check if engine is available.
  Future<bool> checkAnkiCollection({OfficialAnkiEngine? engine}) async {
    var resolvedEngine = _resolveEngine(engine);
    if (resolvedEngine == null) {
      try {
        await OfficialAnkiCompositionRoot.requireImporter();
        resolvedEngine = OfficialAnkiCompositionRoot.engine;
      } catch (_) {}
    }
    if (resolvedEngine == null) return false;
    try {
      await resolvedEngine.checkCollection();
      return true;
    } catch (e) {
      debugPrint('[DatabaseDoctorService] checkCollection failed: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper queries
  // ─────────────────────────────────────────────────────────────────────────

  static Future<int> _pragmaInt(CourseDatabase db, String sql) async {
    final row = await db.customSelect(sql).getSingle();
    return row.data.values.first as int;
  }

  static Future<int> _countTable(CourseDatabase db, String table) async {
    final row =
        await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle();
    return row.data['c'] as int? ?? 0;
  }

  static Future<String?> _mainDatabasePath(CourseDatabase db) async {
    final rows = await db.customSelect('PRAGMA database_list').get();
    for (final row in rows) {
      if ((row.data['name'] as String?) == 'main') {
        final file = row.data['file'] as String?;
        if (file != null && file.isNotEmpty) return file;
      }
    }
    return null;
  }
}
