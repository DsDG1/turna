import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_pending_imports.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_storage_audit.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  final pkg = File(
    p.join(
      'test',
      'fixtures',
      'anki_official',
      'packages',
      '01-basic-unicode.apkg',
    ),
  );

  ({
    OfficialAnkiDatabase db,
    OfficialAnkiSourceDao sources,
    OfficialAnkiImportAttemptDao attempts,
    FakeOfficialAnkiEngine engine,
    OfficialAnkiPaths paths,
    OfficialAnkiImportOrchestrator orch,
    void Function() dispose,
  }) harness() {
    final db = OfficialAnkiDatabase.memory();
    final sources = OfficialAnkiSourceDao(db);
    final attempts = OfficialAnkiImportAttemptDao(db);
    final engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: pkg.path, notes: 1, cards: 1);
    final root = Directory.systemTemp.createTempSync('turna-life-');
    File('${root.path}/collection.anki2').writeAsBytesSync([1, 2, 3, 4]);
    final paths = OfficialAnkiPaths(
      profileId: 'profile-life-01',
      profileRoot: root,
    );
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = engine;
    OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
    final orch = OfficialAnkiImportOrchestrator(
      engine: engine,
      sources: sources,
      attempts: attempts,
      paths: paths,
    );
    return (
      db: db,
      sources: sources,
      attempts: attempts,
      engine: engine,
      paths: paths,
      orch: orch,
      dispose: () {
        OfficialAnkiCompositionRoot.debugStagingEngineOverride = null;
        OfficialAnkiCompositionRoot.stagingEngine = null;
        OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
        db.close();
        root.deleteSync(recursive: true);
      },
    );
  }

  Future<OfficialAnkiImportResult> stage(
    ({
      OfficialAnkiDatabase db,
      OfficialAnkiSourceDao sources,
      OfficialAnkiImportAttemptDao attempts,
      FakeOfficialAnkiEngine engine,
      OfficialAnkiPaths paths,
      OfficialAnkiImportOrchestrator orch,
      void Function() dispose,
    }) h, {
    String displayName = 'life',
  }) async {
    final imported = await OfficialAnkiImportSaga(
      sources: h.sources,
      attempts: h.attempts,
      paths: h.paths,
    ).startStaging(packagePath: pkg.path, displayName: displayName);
    final cards = h.engine.cards.values.toList();
    if (cards.isNotEmpty) {
      h.sources.upsertCardBatch(sourceId: imported.sourceId, cards: cards);
    }
    return imported;
  }

  test('S0 audit snapshot records counts and bytes', () {
    final h = harness();
    addTearDown(h.dispose);
    final snap = const OfficialAnkiStorageAudit().snapshot(
      catalog: h.db,
      paths: h.paths,
      profileId: h.paths.profileId,
    );
    expect(snap['sourceCardAssociations'], 0);
    expect((snap['files'] as Map)['collection.anki2'], greaterThan(0));
    expect(const OfficialAnkiStorageAudit().encode(snap), contains('files'));
  });

  test('import stays staging/preview_ready until product publish', () async {
    final h = harness();
    addTearDown(h.dispose);
    final imported = await stage(h);
    expect(imported.state, OfficialAnkiSourceState.previewReady);
    expect(h.sources.findById(imported.sourceId)!.state, 'staging');
    final pending = const OfficialAnkiPendingImportStore().listForProfile(
      catalog: h.db,
      profileId: h.paths.profileId,
    );
    expect(pending, isNotEmpty);
    expect(pending.single.phase, 'preview_ready');
  });

  test('cancelActive removes staging without restoreBackup', () async {
    final h = harness();
    addTearDown(h.dispose);
    final imported = await stage(h);
    await OfficialAnkiImportSaga(
      sources: h.sources,
      attempts: h.attempts,
      paths: h.paths,
    ).cancelSource(imported.sourceId);
    expect(h.sources.findById(imported.sourceId), isNull);
    expect(h.engine.restoreCalls, 0);
  });

  test('fault in importingOfficial rolls back to quarantined', () async {
    final h = harness();
    addTearDown(h.dispose);
    h.sources.upsertSource(
      sourceId: 'src-fault',
      profileId: h.paths.profileId,
      sourceHash: 'h-f',
      sourceSize: 1,
      displayName: 'fault',
      state: OfficialAnkiSourceState.importingOfficial.wire,
      backendCommit: 'c',
      nowMillis: 1,
    );
    h.attempts.insert(
      attemptId: 'att-fault',
      sourceId: 'src-fault',
      requestId: 'req',
      state: OfficialAnkiSourceState.importingOfficial.wire,
      nowMillis: 1,
    );
    final recovered = await h.orch.rollbackAttempt(h.attempts.find('att-fault')!);
    expect(recovered.state, OfficialAnkiSourceState.quarantined);
    expect(h.engine.restoreCalls, 0);
  });

  test('exclusive media is GC’d; shared media is kept', () async {
    final h = harness();
    addTearDown(h.dispose);
    h.engine.mediaFiles['only-a.mp3'] = 10 * 1024 * 1024;
    h.engine.mediaFiles['shared.mp3'] = 2048;
    h.engine.referencedMedia.add('shared.mp3');
    final dry = await h.engine.gcUnusedMedia(dryRun: true);
    expect(dry.unusedFiles, 1);
    expect(h.engine.mediaFiles.containsKey('only-a.mp3'), isTrue);
    final gone = await h.engine.gcUnusedMedia(dryRun: false);
    expect(gone.removedFiles, 1);
    expect(h.engine.mediaFiles.containsKey('only-a.mp3'), isFalse);
    expect(h.engine.mediaFiles.containsKey('shared.mp3'), isTrue);
  });

  test('maintenance jobs merge by kind and can run', () async {
    final h = harness();
    addTearDown(h.dispose);
    final jobs = OfficialAnkiMaintenanceJobDao(h.db);
    final now = DateTime.now().millisecondsSinceEpoch;
    final a = jobs.enqueue(
      profileId: h.paths.profileId,
      kind: OfficialAnkiMaintenanceKind.mediaGc,
      nowMillis: now,
    );
    final b = jobs.enqueue(
      profileId: h.paths.profileId,
      kind: OfficialAnkiMaintenanceKind.mediaGc,
      nowMillis: now,
    );
    expect(a, b);
    h.engine.mediaFiles['x.bin'] = 12;
    final ran = await OfficialAnkiMaintenanceRunner(
      catalog: h.db,
      paths: h.paths,
      engine: h.engine,
    ).runPending(profileId: h.paths.profileId);
    expect(ran, greaterThan(0));
  });

  test('compactCollection invalid_state completes the job instead of retrying',
      () async {
    final h = harness();
    addTearDown(h.dispose);
    h.engine.failCompactInvalidState = true;
    final jobs = OfficialAnkiMaintenanceJobDao(h.db);
    jobs.enqueue(
      profileId: h.paths.profileId,
      kind: OfficialAnkiMaintenanceKind.compactCollection,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
    );
    final ran = await OfficialAnkiMaintenanceRunner(
      catalog: h.db,
      paths: h.paths,
      engine: h.engine,
    ).runPending(profileId: h.paths.profileId);
    expect(ran, 1);
    expect(jobs.pending(profileId: h.paths.profileId), isEmpty);
  });

  test('catalog schema is v14 with strictly 5 core tables', () {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final version =
        db.handle.select('PRAGMA user_version').first['user_version'] as int;
    expect(version, kOfficialAnkiCatalogSchemaVersion);
    expect(version, 14);
    final tables = db.handle
        .select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
        .map((row) => row['name'] as String)
        .toSet();
    expect(
      tables,
      equals({
        'anki_sources',
        'anki_source_cards',
        'anki_import_attempts',
        'anki_maintenance_jobs',
        'anki_maintenance_leases',
      }),
    );
  });
}
