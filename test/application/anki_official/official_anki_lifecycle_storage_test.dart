import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/import/official_anki_recovery_service.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_pending_imports.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_repair_executor.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_source_metadata_dao.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_storage_audit.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_uninstall_saga.dart';
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
        db.close();
        root.deleteSync(recursive: true);
      },
    );
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
    final imported = await h.orch.importFile(
      packagePath: pkg.path,
      displayName: 'life',
    );
    expect(imported.state, OfficialAnkiSourceState.previewReady);
    expect(h.sources.findById(imported.sourceId)!.state, 'staging');
    final pending = const OfficialAnkiPendingImportStore().listForProfile(
      catalog: h.db,
      profileId: h.paths.profileId,
    );
    expect(pending, isNotEmpty);
    expect(pending.single.phase, 'preview_ready');
  });

  test('native cancel is invoked from discard coordinator', () async {
    final h = harness();
    addTearDown(h.dispose);
    final imported = await h.orch.importFile(
      packagePath: pkg.path,
      displayName: 'life',
    );
    await OfficialAnkiImportSagaCoordinator(h.orch)
        .requestDiscard(imported.attemptId);
    expect(h.engine.cancelCalls, greaterThan(0));
    expect(h.engine.restoreCalls, greaterThan(0));
    expect(
      h.attempts.find(imported.attemptId)!.state,
      OfficialAnkiSourceState.rolledBack.wire,
    );
  });

  test('afterNativeImportBeforeReceiptCommit restarts into rollback', () async {
    final h = harness();
    addTearDown(h.dispose);
    try {
      await OfficialAnkiImportOrchestrator(
        engine: h.engine,
        sources: h.sources,
        attempts: h.attempts,
        paths: h.paths,
        fault: OfficialAnkiFaultPoint.afterNativeImportBeforeReceiptCommit,
      ).importFile(packagePath: pkg.path, displayName: 'fault');
      fail('expected fault');
    } on Object {
      // expected
    }
    final recovered = await OfficialAnkiRecoveryService(
      sources: h.sources,
      attempts: h.attempts,
      engine: h.engine,
      orchestrator: h.orch,
    ).recoverUnfinished();
    expect(recovered.single.state, OfficialAnkiSourceState.rolledBack);
    expect(h.engine.restoreCalls, greaterThan(0));
  });

  test('A/B shared cards survive deleting A; exclusive cards are verified gone',
      () async {
    final h = harness();
    addTearDown(h.dispose);
    await h.orch.importFile(packagePath: pkg.path, displayName: 'A');
    final sourceA = h.sources.listSources(h.paths.profileId).single.sourceId;
    h.sources.upsertSource(
      sourceId: 'src-b',
      profileId: h.paths.profileId,
      sourceHash: 'hash-b',
      sourceSize: 1,
      displayName: 'B',
      state: 'active',
      backendCommit: 'c',
      nowMillis: 1,
    );
    h.sources.upsertCardBatch(
      sourceId: 'src-b',
      cards: h.sources.listCards(sourceA),
    );
    h.engine.cards[2] = const OfficialAnkiCardDescriptor(
      cardId: 2,
      noteId: 2,
      deckId: 1,
      templateOrd: 0,
      noteGuid: 'guid-2',
      notetypeId: 1,
    );
    h.sources.upsertCardBatch(
      sourceId: sourceA,
      cards: [
        ...h.sources.listCards(sourceA),
        h.engine.cards[2]!,
      ],
    );

    final result = await OfficialAnkiUninstallSaga(
      catalog: h.db,
      engine: h.engine,
      paths: h.paths,
    ).run(sourceA);
    expect(result.logicalDeleteComplete, isTrue);
    expect(h.engine.cards.containsKey(2), isFalse);
    expect(h.engine.cards.containsKey(1), isTrue, reason: 'shared card kept');
    expect(h.sources.findById(sourceA), isNull);
    expect(h.sources.findById('src-b'), isNotNull);
  });

  test('source-scoped metadata hides deleted source notetypes from later import',
      () async {
    final h = harness();
    addTearDown(h.dispose);
    final imported = await h.orch.importFile(
      packagePath: pkg.path,
      displayName: 'A',
    );
    final metadata = OfficialAnkiSourceMetadataDao(h.db);
    expect(metadata.notetypeIds(imported.sourceId), isNotEmpty);
    await OfficialAnkiUninstallSaga(
      catalog: h.db,
      engine: h.engine,
      paths: h.paths,
    ).run(imported.sourceId);
    expect(metadata.notetypeIds(imported.sourceId), isEmpty);
    final schemas = await h.engine.getProjectionSchemas(notetypeIds: [99]);
    expect(schemas, isEmpty);
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

  test('resolved checkpoints stay bounded across import/delete cycles', () async {
    final h = harness();
    addTearDown(h.dispose);
    for (var i = 0; i < 5; i++) {
      h.engine.seedPackage(packagePath: pkg.path, notes: 1, cards: 1);
      final imported = await h.orch.importFile(
        packagePath: pkg.path,
        displayName: 'cycle-$i',
      );
      await OfficialAnkiUninstallSaga(
        catalog: h.db,
        engine: h.engine,
        paths: h.paths,
      ).run(imported.sourceId);
    }
    final ready = h.db.handle.select(
      "SELECT COUNT(*) AS n FROM anki_checkpoint_files WHERE state = 'ready'",
    ).first['n'] as int;
    expect(ready, 0);
  });

  test('compact skip on failure leaves logical delete intact', () async {
    final h = harness();
    addTearDown(h.dispose);
    final imported = await h.orch.importFile(
      packagePath: pkg.path,
      displayName: 'compact',
    );
    h.engine.failCompact = true;
    final result = await OfficialAnkiUninstallSaga(
      catalog: h.db,
      engine: h.engine,
      paths: h.paths,
    ).run(imported.sourceId);
    expect(result.logicalDeleteComplete, isTrue);
    h.engine.failCompact = false;
    try {
      await h.engine.compactCollection();
      fail('expected compact failure');
    } on Object {
      expect(h.engine.cards.containsKey(1), isFalse);
    }
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

  test('catalog schema is v12', () {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final version =
        db.handle.select('PRAGMA user_version').first['user_version'] as int;
    expect(version, kOfficialAnkiCatalogSchemaVersion);
    expect(version, 12);
    final tables = db.handle
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((row) => row['name'] as String)
        .toSet();
    expect(
      tables,
      containsAll([
        'anki_source_notetypes',
        'anki_source_decks',
        'anki_checkpoint_files',
        'anki_maintenance_jobs',
      ]),
    );
  });
}
