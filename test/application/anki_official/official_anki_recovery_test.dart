import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/import/official_anki_recovery_service.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

void main() {
  final pkg = File(
    p.join('test', 'fixtures', 'anki_official', 'packages', '01-basic-unicode.apkg'),
  );

  ({
    OfficialAnkiDatabase db,
    OfficialAnkiSourceDao sources,
    OfficialAnkiImportAttemptDao attempts,
    FakeOfficialAnkiEngine engine,
    OfficialAnkiPaths paths,
    OfficialAnkiImportOrchestrator orch,
    OfficialAnkiRecoveryService recovery,
    void Function() dispose,
  }) harness() {
    final db = OfficialAnkiDatabase.memory();
    final sources = OfficialAnkiSourceDao(db);
    final attempts = OfficialAnkiImportAttemptDao(db);
    final engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: pkg.path, notes: 1, cards: 1);
    final root = Directory.systemTemp.createTempSync('turna-rec-');
    final paths = OfficialAnkiPaths(profileId: 'profile-recov-01', profileRoot: root);
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
      recovery: OfficialAnkiRecoveryService(
        sources: sources,
        attempts: attempts,
        engine: engine,
        orchestrator: orch,
      ),
      dispose: () {
        OfficialAnkiCompositionRoot.debugStagingEngineOverride = null;
        OfficialAnkiCompositionRoot.stagingEngine = null;
        OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
        db.close();
        root.deleteSync(recursive: true);
      },
    );
  }

  test('incomplete staging recover does not write live Collection', () async {
    final h = harness();
    addTearDown(h.dispose);
    h.sources.upsertSource(
      sourceId: 'src-stage',
      profileId: h.paths.profileId,
      sourceHash: 'h',
      sourceSize: 1,
      displayName: 's',
      state: OfficialAnkiSourceState.staging.wire,
      backendCommit: 'c',
      nowMillis: 1,
    );
    h.attempts.insert(
      attemptId: 'att-stage',
      sourceId: 'src-stage',
      requestId: 'req',
      state: OfficialAnkiSourceState.staging.wire,
      nowMillis: 1,
      phase: OfficialAnkiAttemptPhase.stagingImporting,
      stagingPath: Directory('${h.paths.profileRoot.path}-stg').path,
    );
    final liveBefore = h.engine.importCount;
    final recovered = await h.recovery.recoverUnfinished();
    expect(recovered.single.state, OfficialAnkiSourceState.cancelled);
    expect(h.engine.importCount, liveBefore);
  });

  test('preview_ready staging recover leaves pending import', () async {
    final h = harness();
    addTearDown(h.dispose);
    h.engine.seedPackage(packagePath: pkg.path, notes: 1, cards: 1);
    final staged = await OfficialAnkiImportSaga(
      sources: h.sources,
      attempts: h.attempts,
      paths: h.paths,
    ).startStaging(packagePath: pkg.path, displayName: 'ready');
    expect(staged.state, OfficialAnkiSourceState.previewReady);
    final liveBefore = h.engine.importCount;
    final recovered = await h.recovery.recoverUnfinished();
    expect(recovered.single.state, OfficialAnkiSourceState.previewReady);
    expect(h.engine.importCount, liveBefore);
    expect(h.sources.findById(staged.sourceId)?.state, isNot('active'));
  });

  test('leftover importing_official without checkpoint is quarantined',
      () async {
    final h = harness();
    addTearDown(h.dispose);
    h.sources.upsertSource(
      sourceId: 'src-old',
      profileId: h.paths.profileId,
      sourceHash: 'old',
      sourceSize: 1,
      displayName: 'old',
      state: OfficialAnkiSourceState.importingOfficial.wire,
      backendCommit: 'c',
      nowMillis: 1,
    );
    h.attempts.insert(
      attemptId: 'att-old',
      sourceId: 'src-old',
      requestId: 'req',
      state: OfficialAnkiSourceState.importingOfficial.wire,
      nowMillis: 1,
    );
    final recovered = await h.recovery.recoverUnfinished();
    expect(recovered.single.state, OfficialAnkiSourceState.quarantined);
    expect(h.engine.restoreCalls, 0);
  });

  test('leftover importing_official with checkpoint restores once', () async {
    final h = harness();
    addTearDown(h.dispose);
    h.sources.upsertSource(
      sourceId: 'src-ck',
      profileId: h.paths.profileId,
      sourceHash: 'ck',
      sourceSize: 1,
      displayName: 'ck',
      state: OfficialAnkiSourceState.importingOfficial.wire,
      backendCommit: 'c',
      nowMillis: 1,
    );
    h.attempts.insert(
      attemptId: 'att-ck',
      sourceId: 'src-ck',
      requestId: 'req',
      state: OfficialAnkiSourceState.importingOfficial.wire,
      nowMillis: 1,
    );
    h.attempts.transition(
      attemptId: 'att-ck',
      expectedState: OfficialAnkiSourceState.importingOfficial.wire,
      nextState: OfficialAnkiSourceState.importingOfficial.wire,
      nowMillis: 2,
      checkpointId: 'bk-fake',
    );
    final recovered = await h.recovery.recoverUnfinished();
    expect(recovered.single.state, OfficialAnkiSourceState.rolledBack);
    expect(h.engine.restoreCalls, 1);
  });

  test('unknown attempt state is never promoted to active', () {
    final h = harness();
    addTearDown(h.dispose);
    h.sources.upsertSource(
      sourceId: 'src-unknown',
      profileId: h.paths.profileId,
      sourceHash: 'abc',
      sourceSize: 1,
      displayName: 'x',
      state: 'weird',
      backendCommit: 'c',
      nowMillis: 1,
    );
    h.attempts.insert(
      attemptId: 'att-unknown',
      sourceId: 'src-unknown',
      requestId: 'req-unknown',
      state: 'weird',
      nowMillis: 1,
    );
    final decision =
        decideOfficialAnkiRecovery(h.attempts.find('att-unknown')!);
    expect(decision.state.isActive, isFalse);
    expect(decision.state, OfficialAnkiSourceState.needsReconciliation);
  });
}
