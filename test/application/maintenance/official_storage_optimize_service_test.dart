import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/maintenance/official_storage_optimize_service.dart';

void main() {
  test('force compact fails closed without catalog or paths', () async {
    final result =
        await const OfficialStorageOptimizeService().runForceCompact();
    expect(result.ok, isFalse);
    expect(result.errorCode, 'capability_missing');
    expect(result.completedJobs, 0);
  });

  test('force compact bootstraps the engine before enqueuing jobs', () async {
    // Regression (field report 2026-09-01): with no live session the
    // service used to run engine-less and compactCollection degraded to
    // the raw-file path, which cannot rebuild rslib's `COLLATE unicase`
    // indexes. It must bootstrap the same session the due sync opens and
    // run all three jobs through it.
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    final root = Directory.systemTemp.createTempSync('turna-opt-boot-');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
    final engine = FakeOfficialAnkiEngine();
    var bootstraps = 0;
    final result = await OfficialStorageOptimizeService(
      ensureEngine: () async {
        bootstraps++;
        return engine;
      },
    ).runForceCompact(
      catalog: catalog,
      paths: OfficialAnkiPaths(profileId: 'p-opt-01', profileRoot: root),
    );
    expect(result.ok, isTrue);
    expect(result.completedJobs, 3);
    expect(bootstraps, 1);
    expect(engine.compactCalls, 1);
  });

  test('force compact fails closed when the engine cannot bootstrap',
      () async {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    final root = Directory.systemTemp.createTempSync('turna-opt-fail-');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
    final result = await OfficialStorageOptimizeService(
      ensureEngine: () async => throw StateError('engine unavailable'),
    ).runForceCompact(
      catalog: catalog,
      paths: OfficialAnkiPaths(profileId: 'p-opt-01', profileRoot: root),
    );
    expect(result.ok, isFalse);
    expect(result.errorCode, 'importer_not_ready');
    expect(result.completedJobs, 0);
    final count = catalog.handle.select(
      'SELECT COUNT(*) AS n FROM anki_maintenance_jobs',
    ).first['n'] as int;
    expect(count, 0, reason: 'fail closed must not enqueue zombie jobs');
  });
}
