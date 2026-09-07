import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/maintenance/database_doctor_service.dart';
import 'package:turna/application/maintenance/storage_inventory_service.dart';

import '../../helpers/in_memory_course_db.dart';

class _FakeScanner implements StorageInventoryService {
  const _FakeScanner({this.orphans = const []});

  final List<StorageArtifactReport> orphans;

  @override
  Future<StorageInventoryReport> scan() async => StorageInventoryReport(
        artifacts: orphans,
        databaseWalBytes: 0,
        databaseShmBytes: 0,
        freelistBytes: 0,
        aiCacheEntries: 0,
        scannedAt: DateTime(2026, 9, 7),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  group('DatabaseDoctorService', () {
    test('inspectHealth reports healthy for standalone course database',
        () async {
      final courseDb = emptyInMemoryCourseDatabase();
      addTearDown(courseDb.close);

      const doctor = DatabaseDoctorService();
      final report = await doctor.inspectHealth(
        course: courseDb,
        scanner: const _FakeScanner(),
      );

      expect(report.courseDb.integrityOk, isTrue);
      expect(report.courseDb.foreignKeyViolations, 0);
      expect(report.ankiDb.isConfigured, isFalse);
      expect(report.ankiDb.integrityOk, isTrue);
      expect(report.storage.orphanCount, 0);
      expect(report.isAllHealthy, isTrue);
    });

    test('optimizeCourseDb succeeds and compacts in-memory database', () async {
      final courseDb = emptyInMemoryCourseDatabase();
      addTearDown(courseDb.close);

      const doctor = DatabaseDoctorService();
      final result = await doctor.optimizeCourseDb(course: courseDb);

      expect(result.ok, isTrue);
      expect(result.courseDbBytesBefore, greaterThanOrEqualTo(0));
      expect(result.courseDbBytesAfter, greaterThanOrEqualTo(0));
    });

    test('optimizeAll succeeds gracefully without Anki catalog', () async {
      final courseDb = emptyInMemoryCourseDatabase();
      addTearDown(courseDb.close);

      const doctor = DatabaseDoctorService();
      final result = await doctor.optimizeAll(course: courseDb);

      expect(result.ok, isTrue);
      expect(result.ankiJobsCompleted, 0);
    });

    test('maintenance job retry, delete, and clear operations', () async {
      final catalog = OfficialAnkiDatabase.memory();
      addTearDown(catalog.close);
      final jobDao = OfficialAnkiMaintenanceJobDao(catalog);
      const profileId = 'profile-test';

      final jobId1 = jobDao.enqueue(
        profileId: profileId,
        kind: OfficialAnkiMaintenanceKind.compactCatalog,
        nowMillis: 100,
      );
      final jobId2 = jobDao.enqueue(
        profileId: profileId,
        kind: OfficialAnkiMaintenanceKind.mediaGc,
        nowMillis: 100,
      );

      jobDao.markFailed(
        jobId: jobId1,
        nowMillis: 200,
        errorCode: 'test_failure',
        retryable: false,
      );

      expect(jobDao.recentFailed(profileId: profileId).length, 1);

      // Test retryJob
      const doctor = DatabaseDoctorService();
      jobDao.retryJob(jobId: jobId1, nowMillis: 300);
      expect(jobDao.recentFailed(profileId: profileId).length, 0);
      expect(jobDao.pending(profileId: profileId).length, 2);

      // Test deleteJob
      doctor.deleteJob(jobId: jobId2, catalog: catalog);
      expect(jobDao.pending(profileId: profileId).length, 1);

      // Re-fail and clear
      jobDao.markFailed(
        jobId: jobId1,
        nowMillis: 400,
        errorCode: 'fail_again',
        retryable: false,
      );
      expect(jobDao.recentFailed(profileId: profileId).length, 1);

      final cleared = doctor.clearFailedJobs(
        catalog: catalog,
        paths: OfficialAnkiPaths(
          profileId: profileId,
          profileRoot: Directory.systemTemp,
        ),
      );
      expect(cleared, 1);
      expect(jobDao.recentFailed(profileId: profileId).length, 0);
    });

    test('checkCourseIntegrity and rebuildCourseIndexes succeed', () async {
      final courseDb = emptyInMemoryCourseDatabase();
      addTearDown(courseDb.close);

      const doctor = DatabaseDoctorService();
      final integrity = await doctor.checkCourseIntegrity(course: courseDb);
      expect(integrity, 'ok');

      await expectLater(
        doctor.rebuildCourseIndexes(course: courseDb),
        completes,
      );
    });

    test('inspectHealth correctly reports orphan storage artifacts', () async {
      final courseDb = emptyInMemoryCourseDatabase();
      addTearDown(courseDb.close);

      final fakeOrphans = [
        const StorageArtifactReport(
          category: StorageArtifactCategory.legacyAnkiMedia,
          ownerId: 'orphan-1',
          label: 'media/orphan-1',
          physicalBytes: 2048,
          fileCount: 3,
          cleanupPolicy: StorageCleanupPolicy.confirmOnly,
          orphaned: true,
        ),
      ];

      const doctor = DatabaseDoctorService();
      final report = await doctor.inspectHealth(
        course: courseDb,
        scanner: _FakeScanner(orphans: fakeOrphans),
      );

      expect(report.storage.orphanCount, 1);
      expect(report.storage.orphanBytes, 2048);
      expect(report.isAllHealthy, isFalse);
      expect(report.totalIssuesCount, 1);
    });
  });
}
