import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_source_reconciler.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

const _profile = 'profile-default-01';

OfficialAnkiSourceEvidence _base({
  String? sourceId,
  String? importId,
  String sourceHash = 'hash-a',
  OfficialAnkiPersistedOwner? recordedOwner,
  String? unificationBackend,
  String? migrationRecordedKind,
  String? migrationOfficialSourceId,
  String? migrationState,
  String? officialSourceState,
  int officialCardCount = 0,
  bool collectionPresent = false,
  bool projectionPresent = false,
  int placementCount = 0,
  int identityRowCount = 0,
  bool legacyImportPresent = false,
  int legacyNoteCount = 0,
  int legacyCardCount = 0,
  int legacySrsCount = 0,
  bool cardinalityConflict = false,
  bool identityConsistent = true,
  bool fromLegacyPendingPath = false,
}) {
  return OfficialAnkiSourceEvidence(
    profileId: _profile,
    sourceId: sourceId,
    importId: importId,
    sourceHash: sourceHash,
    recordedOwner: recordedOwner,
    unificationBackend: unificationBackend,
    migrationRecordedKind: migrationRecordedKind,
    migrationOfficialSourceId: migrationOfficialSourceId,
    migrationState: migrationState,
    officialSourceState: officialSourceState,
    officialCardCount: officialCardCount,
    collectionPresent: collectionPresent,
    projectionPresent: projectionPresent,
    placementCount: placementCount,
    identityRowCount: identityRowCount,
    legacyImportPresent: legacyImportPresent,
    legacyNoteCount: legacyNoteCount,
    legacyCardCount: legacyCardCount,
    legacySrsCount: legacySrsCount,
    cardinalityConflict: cardinalityConflict,
    identityConsistent: identityConsistent,
    fromLegacyPendingPath: fromLegacyPendingPath,
  );
}

String _catalogFingerprint(OfficialAnkiDatabase db) {
  final version =
      db.handle.select('PRAGMA user_version').first['user_version'] as int;
  final tables = db.handle.select(
    "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
  );
  final parts = <String>['v=$version'];
  for (final table in tables) {
    final name = table['name'] as String;
    if (name.startsWith('sqlite_')) continue;
    final n =
        db.handle.select('SELECT COUNT(*) AS n FROM $name').first['n'] as int;
    parts.add('$name=$n');
  }
  final cards = db.handle.select(
    'SELECT source_id, card_id FROM anki_source_cards '
    'ORDER BY source_id, card_id',
  );
  for (final row in cards) {
    parts.add('card:${row['source_id']}:${row['card_id']}');
  }
  final journal = db.handle.select(
    'SELECT operation_id, current_step, evidence_hash '
    'FROM anki_source_reconciliation_journal ORDER BY operation_id',
  );
  for (final row in journal) {
    parts.add(
      'j:${row['operation_id']}:${row['current_step']}:${row['evidence_hash']}',
    );
  }
  return parts.join('|');
}

void main() {
  const reconciler = OfficialAnkiSourceReconciler();

  group('§7.2 state matrix', () {
    test('cleanOfficial', () {
      final d = reconciler.classify(
        _base(
          sourceId: 'src-o',
          recordedOwner: OfficialAnkiPersistedOwner.official,
          migrationRecordedKind: 'official',
          unificationBackend: 'official',
          officialSourceState: 'active',
          officialCardCount: 3,
          collectionPresent: true,
          projectionPresent: true,
          placementCount: 3,
          identityRowCount: 3,
        ),
      );
      expect(d.state, OfficialAnkiSourceReconcileState.cleanOfficial);
      expect(d.autoAction, OfficialAnkiReconcileAutoAction.useNormally);
      expect(d.intendedOwner, OfficialAnkiPersistedOwner.official);
    });

    test('cleanLegacy', () {
      final d = reconciler.classify(
        _base(
          importId: 'imp-l',
          recordedOwner: OfficialAnkiPersistedOwner.legacy,
          migrationRecordedKind: 'legacy',
          unificationBackend: 'legacyTurna',
          legacyImportPresent: true,
          legacyNoteCount: 2,
          legacyCardCount: 2,
          legacySrsCount: 2,
        ),
      );
      expect(d.state, OfficialAnkiSourceReconcileState.cleanLegacy);
      expect(d.autoAction, OfficialAnkiReconcileAutoAction.queueMigration);
    });

    test('mirroredConsistent', () {
      final d = reconciler.classify(
        _base(
          sourceId: 'src-m',
          importId: 'imp-m',
          recordedOwner: OfficialAnkiPersistedOwner.official,
          migrationRecordedKind: 'official',
          unificationBackend: 'official',
          officialSourceState: 'active',
          officialCardCount: 5,
          collectionPresent: true,
          projectionPresent: true,
          placementCount: 5,
          identityRowCount: 5,
          legacyImportPresent: true,
          legacyNoteCount: 5,
          legacyCardCount: 5,
          legacySrsCount: 5,
          identityConsistent: true,
        ),
      );
      expect(d.state, OfficialAnkiSourceReconcileState.mirroredConsistent);
      expect(
        d.autoAction,
        OfficialAnkiReconcileAutoAction.freezeAndChooseOwner,
      );
    });

    test('ownerOfficialCollectionMissing', () {
      final d = reconciler.classify(
        _base(
          sourceId: 'src-miss',
          recordedOwner: OfficialAnkiPersistedOwner.official,
          migrationRecordedKind: 'official',
          officialSourceState: 'active',
          officialCardCount: 0,
          collectionPresent: false,
          projectionPresent: true,
          placementCount: 0,
        ),
      );
      expect(
        d.state,
        OfficialAnkiSourceReconcileState.ownerOfficialCollectionMissing,
      );
      expect(
        d.autoAction,
        OfficialAnkiReconcileAutoAction.failClosedRepairFromBackup,
      );
    });

    test('ownerOfficialProjectionMissing', () {
      final d = reconciler.classify(
        _base(
          sourceId: 'src-proj',
          recordedOwner: OfficialAnkiPersistedOwner.official,
          migrationRecordedKind: 'official',
          unificationBackend: 'official',
          officialSourceState: 'active',
          officialCardCount: 4,
          collectionPresent: true,
          projectionPresent: false,
          placementCount: 0,
          identityRowCount: 0,
        ),
      );
      expect(
        d.state,
        OfficialAnkiSourceReconcileState.ownerOfficialProjectionMissing,
      );
      expect(d.autoAction, OfficialAnkiReconcileAutoAction.rebuildProjection);
      expect(d.repairPlan, isNotNull);
      expect(d.repairPlan!.mutatesScheduler, isFalse);
      expect(d.repairPlan!.mutatesRevlog, isFalse);
      expect(d.repairPlan!.mutatesCollectionCards, isFalse);
      expect(d.repairPlan!.expectedOfficialCardCount, 4);
    });

    test('ownerLegacySrsMissing', () {
      final d = reconciler.classify(
        _base(
          importId: 'imp-srs',
          recordedOwner: OfficialAnkiPersistedOwner.legacy,
          migrationRecordedKind: 'legacy',
          legacyImportPresent: true,
          legacyNoteCount: 3,
          legacyCardCount: 3,
          legacySrsCount: 0,
        ),
      );
      expect(d.state, OfficialAnkiSourceReconcileState.ownerLegacySrsMissing);
      expect(
        d.autoAction,
        OfficialAnkiReconcileAutoAction.quarantineNoFakeMigration,
      );
    });

    test('ownerMismatch does not auto-pick larger side', () {
      final d = reconciler.classify(
        _base(
          sourceId: 'src-big',
          importId: 'imp-small',
          // Official catalog has more cards than Legacy — still must not
          // invent Official as intendedOwner when claims disagree.
          migrationRecordedKind: 'legacy',
          unificationBackend: 'official',
          officialSourceState: 'active',
          officialCardCount: 100,
          collectionPresent: true,
          projectionPresent: true,
          placementCount: 100,
          legacyImportPresent: true,
          legacyNoteCount: 2,
          legacyCardCount: 2,
          legacySrsCount: 2,
        ),
      );
      expect(d.state, OfficialAnkiSourceReconcileState.ownerMismatch);
      expect(d.intendedOwner, isNull);
      expect(
        d.autoAction,
        OfficialAnkiReconcileAutoAction.isolateAndPlanRepair,
      );
      expect(d.reasons, contains('persisted_owner_claims_disagree'));
    });

    test('pendingCleanup', () {
      final d = reconciler.classify(
        _base(
          sourceId: 'src-pc',
          recordedOwner: OfficialAnkiPersistedOwner.official,
          migrationRecordedKind: 'official',
          officialSourceState: 'pending_cleanup',
          officialCardCount: 1,
          collectionPresent: true,
        ),
      );
      expect(d.state, OfficialAnkiSourceReconcileState.pendingCleanup);
      expect(d.autoAction, OfficialAnkiReconcileAutoAction.retryCleanup);
    });

    test('legacyPendingMigration', () {
      final d = reconciler.classify(
        _base(
          importId: 'imp-old',
          recordedOwner: OfficialAnkiPersistedOwner.legacy,
          migrationRecordedKind: 'legacy',
          migrationState: 'awaitingPackage',
          legacyImportPresent: true,
          legacyNoteCount: 1,
          legacyCardCount: 1,
          legacySrsCount: 1,
          fromLegacyPendingPath: true,
        ),
      );
      expect(
        d.state,
        OfficialAnkiSourceReconcileState.legacyPendingMigration,
      );
      expect(d.autoAction, OfficialAnkiReconcileAutoAction.readOnlyAwaitW8);
    });

    test('unknownQuarantined on cardinality conflict', () {
      final d = reconciler.classify(
        _base(
          sourceId: 'src-q',
          recordedOwner: OfficialAnkiPersistedOwner.official,
          migrationRecordedKind: 'official',
          officialSourceState: 'active',
          officialCardCount: 10,
          collectionPresent: true,
          projectionPresent: true,
          placementCount: 10,
          cardinalityConflict: true,
        ),
      );
      expect(d.state, OfficialAnkiSourceReconcileState.unknownQuarantined);
      expect(
        d.autoAction,
        OfficialAnkiReconcileAutoAction.diagnoseExportOnly,
      );
    });

    test('never invents owner from missing persisted evidence', () {
      final d = reconciler.classify(
        _base(
          sourceId: 'src-flagless',
          officialSourceState: 'active',
          officialCardCount: 2,
          collectionPresent: true,
          projectionPresent: true,
          placementCount: 2,
          identityRowCount: 2,
        ),
      );
      expect(d.state, OfficialAnkiSourceReconcileState.unknownQuarantined);
      expect(d.intendedOwner, isNull);
      expect(
        d.reasons,
        contains('complete_surfaces_but_no_persisted_owner'),
      );
    });
  });

  group('read-only census', () {
    test('classifies fixture matrix without touching catalog', () async {
      final db = OfficialAnkiDatabase.memory();
      addTearDown(db.close);

      OfficialAnkiSourceDao(db).upsertSource(
        sourceId: 'src-ro',
        profileId: _profile,
        sourceHash: 'hash-ro',
        sourceSize: 1,
        displayName: 'ro',
        state: 'active',
        backendCommit: 't',
        nowMillis: 1,
      );

      final before = _catalogFingerprint(db);
      final beforeVersion = db.handle
          .select('PRAGMA user_version')
          .first['user_version'] as int;

      final fixtures = <OfficialAnkiSourceEvidence>[
        _base(
          sourceId: 'src-o',
          recordedOwner: OfficialAnkiPersistedOwner.official,
          migrationRecordedKind: 'official',
          unificationBackend: 'official',
          officialSourceState: 'active',
          officialCardCount: 1,
          collectionPresent: true,
          projectionPresent: true,
          placementCount: 1,
          identityRowCount: 1,
        ),
        _base(
          importId: 'imp-l',
          recordedOwner: OfficialAnkiPersistedOwner.legacy,
          migrationRecordedKind: 'legacy',
          unificationBackend: 'legacyTurna',
          legacyImportPresent: true,
          legacyNoteCount: 1,
          legacyCardCount: 1,
          legacySrsCount: 1,
        ),
      ];

      final report = await const OfficialAnkiSourceCensusService().collect(
        reader: ListOfficialAnkiSourceEvidenceReader(fixtures),
        profileId: _profile,
        nowMillis: 42,
      );

      expect(report.rows, hasLength(2));
      expect(
        report.rows.map((r) => r.decision.state).toSet(),
        {
          OfficialAnkiSourceReconcileState.cleanOfficial,
          OfficialAnkiSourceReconcileState.cleanLegacy,
        },
      );
      expect(report.toJson()['rows'], isA<List>());
      final encoded = report.toJson().toString();
      expect(encoded.contains('front'), isFalse);
      expect(encoded.contains('cardText'), isFalse);

      expect(_catalogFingerprint(db), before);
      expect(
        db.handle.select('PRAGMA user_version').first['user_version'],
        beforeVersion,
      );
    });

    test('catalog reader is SELECT-only', () async {
      final db = OfficialAnkiDatabase.memory();
      addTearDown(db.close);
      final sources = OfficialAnkiSourceDao(db);
      sources.upsertSource(
        sourceId: 'src-cat',
        profileId: _profile,
        sourceHash: 'hash-cat',
        sourceSize: 2,
        displayName: 'cat',
        state: 'active',
        backendCommit: 't',
        nowMillis: 1,
      );
      db.handle.execute(
        'INSERT INTO anki_source_cards '
        '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
        "VALUES ('src-cat', 1, 1, 1, 'g', 0)",
      );
      db.handle.execute(
        'INSERT INTO anki_source_projection_state '
        '(source_id, state, projected_card_count) '
        "VALUES ('src-cat', 'ready', 1)",
      );
      OfficialAnkiMigrationDao(db).insertObservingOfficial(
        migrationId: 'mig-cat',
        profileId: _profile,
        legacyImportId: 'imp-cat',
        officialSourceId: 'src-cat',
        sourceHash: 'hash-cat',
        nowMillis: 2,
        cardCount: 1,
      );

      final before = _catalogFingerprint(db);
      final report = await const OfficialAnkiSourceCensusService().collect(
        reader: CatalogOfficialAnkiSourceEvidenceReader(db),
        profileId: _profile,
        nowMillis: 99,
      );
      expect(report.rows, hasLength(1));
      expect(_catalogFingerprint(db), before);
      expect(
        report.rows.single.decision.state,
        OfficialAnkiSourceReconcileState.cleanOfficial,
      );
    });
  });

  group('projection rebuild plan', () {
    test('stub forbids scheduler and revlog mutation', () {
      const plan = OfficialAnkiProjectionRebuildPlan(
        sourceId: 'src-p',
        profileId: _profile,
        expectedOfficialCardCount: 7,
      );
      expect(plan.mutatesScheduler, isFalse);
      expect(plan.mutatesRevlog, isFalse);
      expect(plan.mutatesCollectionCards, isFalse);

      final db = OfficialAnkiDatabase.memory();
      addTearDown(db.close);
      OfficialAnkiSourceDao(db).upsertSource(
        sourceId: 'src-p',
        profileId: _profile,
        sourceHash: 'h',
        sourceSize: 1,
        displayName: 'p',
        state: 'active',
        backendCommit: 't',
        nowMillis: 1,
      );
      db.handle.execute(
        'INSERT INTO anki_scheduler_mutations '
        '(mutation_id, profile_id, card_id, queue_epoch, state, '
        'created_at_millis, updated_at_millis) '
        "VALUES ('m1', '$_profile', 1, 0, 'committed', 1, 1)",
      );
      final beforeMutations = db.handle
          .select('SELECT * FROM anki_scheduler_mutations ORDER BY mutation_id')
          .map((r) => r['mutation_id'])
          .toList();

      db.handle.execute(
        'INSERT OR REPLACE INTO anki_source_projection_state '
        '(source_id, state, projected_card_count, source_fingerprint) '
        "VALUES ('src-p', 'ready', ${plan.expectedOfficialCardCount}, 'fp')",
      );

      final afterMutations = db.handle
          .select('SELECT * FROM anki_scheduler_mutations ORDER BY mutation_id')
          .map((r) => r['mutation_id'])
          .toList();
      expect(afterMutations, beforeMutations);
      expect(plan.mutatesRevlog, isFalse);
    });
  });

  group('reconciliation journal', () {
    test('records §7.3 fields and resumes after mid-step kill', () {
      final db = OfficialAnkiDatabase.memory();
      addTearDown(db.close);
      final journal = OfficialAnkiReconciliationJournalDao(db);

      final evidence = _base(
        sourceId: 'src-j',
        recordedOwner: OfficialAnkiPersistedOwner.official,
        migrationRecordedKind: 'official',
        officialSourceState: 'active',
        officialCardCount: 2,
        collectionPresent: true,
        projectionPresent: false,
      );
      final decision = reconciler.classify(evidence);
      expect(
        decision.state,
        OfficialAnkiSourceReconcileState.ownerOfficialProjectionMissing,
      );

      final entry = beginReconciliationJournal(
        dao: journal,
        evidence: evidence,
        decision: decision,
        operationId: 'op-1',
        nowMillis: 10,
      );
      expect(entry.beforeState, decision.state);
      expect(entry.evidenceHash, decision.evidenceHash);
      expect(entry.intendedOwner, OfficialAnkiPersistedOwner.official);
      expect(entry.currentStep, OfficialAnkiReconcileJournalStep.scanned);
      expect(entry.retryPolicy, OfficialAnkiReconcileRetryPolicy.resumeFromStep);
      expect(
        entry.rollbackPolicy,
        OfficialAnkiReconcileRollbackPolicy.restoreBackup,
      );

      journal.advance(
        operationId: 'op-1',
        from: OfficialAnkiReconcileJournalStep.scanned,
        to: OfficialAnkiReconcileJournalStep.planned,
        nowMillis: 11,
      );
      journal.advance(
        operationId: 'op-1',
        from: OfficialAnkiReconcileJournalStep.planned,
        to: OfficialAnkiReconcileJournalStep.backedUp,
        nowMillis: 12,
        backupId: 'bak-1',
      );
      journal.advance(
        operationId: 'op-1',
        from: OfficialAnkiReconcileJournalStep.backedUp,
        to: OfficialAnkiReconcileJournalStep.mutating,
        nowMillis: 13,
        mutation: 'projection_rebuild_start',
      );

      journal.quarantineOpenOperation(
        operationId: 'op-1',
        nowMillis: 14,
        lastError: 'kill_mid_step',
      );

      final afterKill = journal.findById('op-1')!;
      expect(
        afterKill.currentStep,
        OfficialAnkiReconcileJournalStep.quarantined,
      );
      expect(afterKill.lastError, 'kill_mid_step');
      expect(afterKill.backupId, 'bak-1');
      expect(afterKill.completedMutations, ['projection_rebuild_start']);
      expect(
        afterKill.retryPolicy,
        OfficialAnkiReconcileRetryPolicy.resumeFromStep,
      );
      expect(afterKill.isTerminal, isTrue);

      expect(journal.listOpen(profileId: _profile), isEmpty);

      beginReconciliationJournal(
        dao: journal,
        evidence: evidence,
        decision: decision,
        operationId: 'op-1-resume',
        nowMillis: 20,
      );
      final resumed = journal.findById('op-1-resume')!;
      expect(resumed.evidenceHash, afterKill.evidenceHash);
      expect(resumed.isResumable, isTrue);
      expect(journal.listOpen(profileId: _profile).map((e) => e.operationId), [
        'op-1-resume',
      ]);
    });

    test('schema v9 creates journal table', () {
      final db = OfficialAnkiDatabase.memory();
      addTearDown(db.close);
      expect(
        db.handle.select('PRAGMA user_version').first['user_version'],
        kOfficialAnkiCatalogSchemaVersion,
      );
      final tables = db.handle.select(
        "SELECT name FROM sqlite_master WHERE name='anki_source_reconciliation_journal'",
      );
      expect(tables, isNotEmpty);
    });
  });

  group('MigrationDao + SourceDao fixtures', () {
    test('mismatch with larger official side still quarantines', () {
      final db = OfficialAnkiDatabase.memory();
      addTearDown(db.close);
      final sources = OfficialAnkiSourceDao(db);
      sources.upsertSource(
        sourceId: 'src-large',
        profileId: _profile,
        sourceHash: 'hash-x',
        sourceSize: 10,
        displayName: 'large',
        state: 'active',
        backendCommit: 't',
        nowMillis: 1,
      );
      for (var i = 1; i <= 5; i++) {
        db.handle.execute(
          'INSERT INTO anki_source_cards '
          '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
          "VALUES ('src-large', $i, $i, 1, 'g$i', 0)",
        );
      }
      final dao = OfficialAnkiMigrationDao(db);
      dao.insertDetected(
        migrationId: 'mig-x',
        profileId: _profile,
        legacyImportId: 'imp-small',
        policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
        sourceHash: 'hash-x',
        legacyCardCount: 1,
        nowMillis: 2,
      );
      dao.setRecordedKind(
        migrationId: 'mig-x',
        recordedKind: 'legacy',
        nowMillis: 3,
      );

      final evidence = OfficialAnkiSourceEvidence(
        profileId: _profile,
        sourceId: 'src-large',
        importId: 'imp-small',
        sourceHash: 'hash-x',
        migrationRecordedKind: dao.recordedKindForSource(
          profileId: _profile,
          legacyImportId: 'imp-small',
        ),
        unificationBackend: 'official',
        officialSourceState: sources.findById('src-large')!.state,
        officialCardCount: sources.cardCount('src-large'),
        collectionPresent: true,
        legacyImportPresent: true,
        legacyCardCount: 1,
        legacyNoteCount: 1,
        legacySrsCount: 1,
      );

      final decision = reconciler.classify(evidence);
      expect(decision.state, OfficialAnkiSourceReconcileState.ownerMismatch);
      expect(decision.intendedOwner, isNull);
      expect(sources.cardCount('src-large'), greaterThan(1));
    });
  });
}
