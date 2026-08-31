import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_startup_recovery.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';

import '../../helpers/in_memory_course_db.dart';

/// First test coverage for [OfficialAnkiStartupRecovery] (step1 task C).
/// Harness mirrors the cold-start wiring in main.dart: read-only catalog
/// locator, no engine session, then run().
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  ({
    OfficialAnkiDatabase catalog,
    OfficialAnkiMaintenanceJobDao jobs,
    OfficialAnkiPaths paths,
    void Function() dispose,
  }) harness() {
    final root = Directory.systemTemp.createTempSync('turna-step1-recovery-');
    final profileRoot = Directory(p.join(root.path, 'official_anki', 'default'))
      ..createSync(recursive: true);
    File(p.join(profileRoot.path, 'collection.anki2')).writeAsBytesSync([1]);
    final catalog = OfficialAnkiDatabase.file(
      p.join(profileRoot.path, 'official_catalog.sqlite'),
    );
    final paths = OfficialAnkiPaths(
      profileId: 'profile-step1-recovery',
      profileRoot: profileRoot,
    );
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    OfficialAnkiCompositionRoot.locatorPaths = paths;
    if (!getIt.isRegistered<CourseDatabase>()) {
      getIt.registerSingleton<CourseDatabase>(emptyInMemoryCourseDatabase());
    }
    return (
      catalog: catalog,
      jobs: OfficialAnkiMaintenanceJobDao(catalog),
      paths: paths,
      dispose: () {
        OfficialAnkiCompositionRoot.readOnlyCatalog = null;
        OfficialAnkiCompositionRoot.locatorPaths = null;
        OfficialAnkiCompositionRoot.debugEngineOverride = null;
        OfficialAnkiCompositionRoot.session = null;
        catalog.handle.execute('DELETE FROM anki_maintenance_leases');
        catalog.close();
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      },
    );
  }

  tearDown(() async {
    await getIt.reset();
  });

  test('no pending work and no engine: ensureEngine is not called', () async {
    final h = harness();
    addTearDown(h.dispose);

    var ensureCalls = 0;
    await OfficialAnkiStartupRecovery(
      ensureEngine: () async => ensureCalls++,
    ).run();

    expect(ensureCalls, 0);
    // Nothing was enqueued, no lease row leaked, catalog still readable.
    expect(h.jobs.pending(profileId: h.paths.profileId), isEmpty);
    expect(
      h.catalog.handle
          .select('SELECT COUNT(*) c FROM anki_maintenance_leases')
          .first['c'],
      0,
    );
  });

  test('pending maintenance job and no engine: engine opens, job completes',
      () async {
    final h = harness();
    addTearDown(h.dispose);
    h.jobs.enqueue(
      profileId: h.paths.profileId,
      kind: OfficialAnkiMaintenanceKind.compactCatalog,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
    );

    var ensureCalls = 0;
    final recovery = OfficialAnkiStartupRecovery(
      ensureEngine: () async {
        ensureCalls++;
        // Same effect as requireImporter(): afterwards
        // CompositionRoot.engine resolves.
        OfficialAnkiCompositionRoot.debugEngineOverride =
            FakeOfficialAnkiEngine();
      },
    );
    await recovery.run();

    expect(ensureCalls, 1);
    final rows = h.catalog.handle
        .select('SELECT state FROM anki_maintenance_jobs')
        .map((row) => row['state'] as String)
        .toList();
    expect(rows, isNotEmpty);
    expect(rows.every((state) => state == 'completed'), isTrue,
        reason: 'startup maintenance must actually run, got $rows');
  });

  test('engine already available: behavior unchanged (regression)', () async {
    final h = harness();
    addTearDown(h.dispose);
    h.jobs.enqueue(
      profileId: h.paths.profileId,
      kind: OfficialAnkiMaintenanceKind.compactCatalog,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
    );
    OfficialAnkiCompositionRoot.debugEngineOverride = FakeOfficialAnkiEngine();

    var ensureCalls = 0;
    await OfficialAnkiStartupRecovery(
      ensureEngine: () async => ensureCalls++,
    ).run();

    // Engine was already resolvable — no need to open one.
    expect(ensureCalls, 0);
    final rows = h.catalog.handle
        .select('SELECT state FROM anki_maintenance_jobs')
        .map((row) => row['state'] as String)
        .toList();
    expect(rows, isNotEmpty);
    expect(rows.every((state) => state == 'completed'), isTrue);
  });
}
