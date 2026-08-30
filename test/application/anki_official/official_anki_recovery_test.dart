import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/import/official_anki_recovery_service.dart';
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
    OfficialAnkiImportOrchestrator Function(OfficialAnkiFaultPoint? fault) orch,
    OfficialAnkiRecoveryService Function(OfficialAnkiImportOrchestrator o)
        recovery,
    void Function() dispose,
  }) harness() {
    final db = OfficialAnkiDatabase.memory();
    final sources = OfficialAnkiSourceDao(db);
    final attempts = OfficialAnkiImportAttemptDao(db);
    final engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: pkg.path, notes: 1, cards: 1);
    final root = Directory.systemTemp.createTempSync('turna-rec-');
    final paths = OfficialAnkiPaths(profileId: 'profile-recov-01', profileRoot: root);
    OfficialAnkiImportOrchestrator make(OfficialAnkiFaultPoint? fault) {
      return OfficialAnkiImportOrchestrator(
        engine: engine,
        sources: sources,
        attempts: attempts,
        paths: paths,
        fault: fault,
        batchSize: 1,
      );
    }

    return (
      db: db,
      sources: sources,
      attempts: attempts,
      engine: engine,
      paths: paths,
      orch: make,
      recovery: (o) => OfficialAnkiRecoveryService(
            sources: sources,
            attempts: attempts,
            engine: engine,
            orchestrator: o,
          ),
      dispose: () {
        db.close();
        root.deleteSync(recursive: true);
      },
    );
  }

  Future<void> expectRecovered({
    required OfficialAnkiFaultPoint point,
    required OfficialAnkiSourceState expected,
  }) async {
    final h = harness();
    addTearDown(h.dispose);
    try {
      await h.orch(point).importFile(
            packagePath: pkg.path,
            displayName: point.name,
          );
      fail('fault $point should throw');
    } on OfficialAnkiException catch (error) {
      expect(error.messageKey, 'official_anki.fault_injected');
    }
    final recovered = await h.recovery(h.orch(null)).recoverUnfinished();
    if (expected == OfficialAnkiSourceState.previewReady) {
      expect(recovered, isNotEmpty);
      expect(recovered.single.state, OfficialAnkiSourceState.previewReady);
      expect(h.sources.findById(recovered.single.sourceId)?.state, 'staging');
    } else if (expected == OfficialAnkiSourceState.active) {
      expect(recovered, isNotEmpty);
      expect(recovered.single.state.isActive, isTrue);
      expect(h.sources.findById(recovered.single.sourceId)?.state, 'active');
    } else {
      if (recovered.isEmpty) {
        expect(expected, isNot(OfficialAnkiSourceState.active));
      } else {
        expect(recovered.single.state, expected);
        expect(recovered.single.state.isActive, isFalse);
      }
    }
    expect(
      h.sources.listSources(h.paths.profileId).where((row) => row.state == 'active'),
      expected == OfficialAnkiSourceState.active ? isNotEmpty : isEmpty,
    );
  }

  test('fault beforeHash leaves no active source', () async {
    await expectRecovered(
      point: OfficialAnkiFaultPoint.beforeHash,
      expected: OfficialAnkiSourceState.failedBeforeImport,
    );
  });

  test('fault afterSourceBeforeCheckpoint is failed_before_import', () async {
    await expectRecovered(
      point: OfficialAnkiFaultPoint.afterSourceBeforeCheckpoint,
      expected: OfficialAnkiSourceState.failedBeforeImport,
    );
  });

  test('importFile after afterCheckpointBeforeImport does not mark active',
      () async {
    final h = harness();
    addTearDown(h.dispose);
    try {
      await h.orch(OfficialAnkiFaultPoint.afterCheckpointBeforeImport).importFile(
            packagePath: pkg.path,
            displayName: 'checkpoint-then-retry',
          );
      fail('fault should throw');
    } on OfficialAnkiException catch (error) {
      expect(error.messageKey, 'official_anki.fault_injected');
    }
    expect(
      h.sources.listSources(h.paths.profileId).map((row) => row.state),
      isNot(contains('active')),
    );
    final retried = await h.orch(null).importFile(
          packagePath: pkg.path,
          displayName: 'checkpoint-then-retry',
        );
    expect(retried.state.isActive, isFalse);
    expect(retried.state, OfficialAnkiSourceState.rolledBack);
    expect(h.sources.findById(retried.sourceId)?.state, isNot('active'));
    expect(h.sources.cardCount(retried.sourceId), 0);
  });

  test('importFile after afterImportBeforeNoteIds does not mark active',
      () async {
    final h = harness();
    addTearDown(h.dispose);
    try {
      await h.orch(OfficialAnkiFaultPoint.afterImportBeforeNoteIds).importFile(
            packagePath: pkg.path,
            displayName: 'import-then-retry',
          );
      fail('fault should throw');
    } on OfficialAnkiException catch (error) {
      expect(error.messageKey, 'official_anki.fault_injected');
    }
    final retried = await h.orch(null).importFile(
          packagePath: pkg.path,
          displayName: 'import-then-retry',
        );
    expect(retried.state.isActive, isFalse);
    expect(retried.state, OfficialAnkiSourceState.rolledBack);
    expect(h.sources.findById(retried.sourceId)?.state, isNot('active'));
  });

  test('fault afterCheckpointBeforeImport rolls back via checkpoint', () async {
    await expectRecovered(
      point: OfficialAnkiFaultPoint.afterCheckpointBeforeImport,
      expected: OfficialAnkiSourceState.rolledBack,
    );
  });

  test('fault duringImportCancel marks cancelled', () async {
    final h = harness();
    addTearDown(h.dispose);
    final result = await h.orch(OfficialAnkiFaultPoint.duringImportCancel).importFile(
          packagePath: pkg.path,
          displayName: 'cancel',
          cancel: true,
        );
    expect(result.state, OfficialAnkiSourceState.cancelled);
    expect(result.state.isActive, isFalse);
    await h.engine.checkCollection();
  });

  test('fault afterImportBeforeNoteIds rolls back via checkpoint', () async {
    await expectRecovered(
      point: OfficialAnkiFaultPoint.afterImportBeforeNoteIds,
      expected: OfficialAnkiSourceState.rolledBack,
    );
  });

  test('fault afterNoteIdsBeforeCards resumes indexing', () async {
    await expectRecovered(
      point: OfficialAnkiFaultPoint.afterNoteIdsBeforeCards,
      expected: OfficialAnkiSourceState.previewReady,
    );
  });

  test('fault afterMidBatchCursor resumes indexing', () async {
    await expectRecovered(
      point: OfficialAnkiFaultPoint.afterMidBatchCursor,
      expected: OfficialAnkiSourceState.previewReady,
    );
  });

  test('fault afterCardsBeforeActive resumes to preview_ready', () async {
    await expectRecovered(
      point: OfficialAnkiFaultPoint.afterCardsBeforeActive,
      expected: OfficialAnkiSourceState.previewReady,
    );
  });

  test('fault afterActiveRestart stays preview_ready and is idempotent', () async {
    final h = harness();
    addTearDown(h.dispose);
    try {
      await h.orch(OfficialAnkiFaultPoint.afterActiveRestart).importFile(
            packagePath: pkg.path,
            displayName: 'active-restart',
          );
      fail('should throw');
    } on OfficialAnkiException {
      // expected
    }
    expect(h.sources.listSources(h.paths.profileId).single.state, 'staging');
    final again = await h.recovery(h.orch(null)).recoverUnfinished();
    expect(again.single.state, OfficialAnkiSourceState.previewReady);
    final second = await h.orch(null).importFile(
          packagePath: pkg.path,
          displayName: 'active-restart',
        );
    expect(second.sourceId, again.single.sourceId);
    expect(second.state, OfficialAnkiSourceState.previewReady);
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
