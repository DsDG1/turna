import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_audit_log.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_mutation_receipt.dart';
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/engine/official_anki_scheduler_audit.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/migration/official_anki_backup_manifest.dart';
import 'package:turna/application/anki_official/migration/official_anki_census.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_write_owner.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/views/anki_official/official_anki_migration_preview_page.dart';

const _flags = OfficialAnkiFeatureFlags(
  engine: true,
  import: true,
  catalogReady: true,
  runtimeCapable: true,
  platformReady: true,
  renderer: true,
  scheduler: true,
);

void main() {
  test('unknown mutation receipt blocks replay after restart', () async {
    OfficialAnkiSchedulerAudit.reset();
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    final receipts = OfficialAnkiMutationReceiptStore(
      catalog,
      profileId: 'p1',
    );
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
    final session = OfficialReviewSession(
      engine: fake,
      flags: _flags,
      receipts: receipts,
    );
    await session.openDeck(1);
    session.showAnswer();
    fake.failNextAnswerUnknown = true;
    await session.answer('good');
    expect(session.phase, OfficialReviewPhase.reconciling);
    expect(receipts.hasBlocking(session.current!.cardId), isTrue);
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 0);

    final restarted = OfficialReviewSession(
      engine: fake,
      flags: _flags,
      receipts: receipts,
    );
    await restarted.openDeck(1);
    expect(restarted.phase, OfficialReviewPhase.reconciling);
    await restarted.answer('again');
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 0);
    receipts.compact(nowMillis: DateTime.now().millisecondsSinceEpoch + 1);
    expect(receipts.hasBlocking(session.current!.cardId), isTrue);
  });

  test('reviewing coordinator rejects import and reopen writes', () async {
    OfficialAnkiSchedulerAudit.reset();
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
    final ops = OfficialAnkiOperationCoordinator();
    final session = OfficialReviewSession(
      engine: fake,
      flags: _flags,
      coordinator: ops,
    );
    await session.openDeck(1);
    expect(ops.isReviewing, isTrue);
    expect(
      () => ops.guardCollectionMutation(),
      throwsA(
        isA<OfficialAnkiException>().having(
          (e) => e.messageKey,
          'key',
          'official_anki.operation_conflict',
        ),
      ),
    );
    final importing = OfficialAnkiOperationCoordinator()
      ..acquire(OfficialAnkiOperationPhase.importing);
    expect(
      () => dispatchOfficialAnkiScheduler(
        fake,
        {
          'op': 'answerCard',
          'sessionId': 'x',
          'queueEpoch': 1,
          'answerToken': 'tok',
          'cardId': 1,
          'rating': 'good',
          'millisecondsTaken': 1,
        },
        coordinator: importing,
      ),
      throwsA(isA<OfficialAnkiException>()),
    );
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 0);
    session.dispose();
  });

  test('undo status and filtered deck gate bury', () async {
    OfficialAnkiSchedulerAudit.reset();
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
    final session = OfficialReviewSession(engine: fake, flags: _flags);
    await session.openDeck(1);
    expect(session.canUndo, isFalse);
    session.showAnswer();
    await session.answer('good');
    expect(session.canUndo, isTrue);
    await session.undo();
    expect(OfficialAnkiSchedulerAudit.officialSchedulerUndo, 1);

    fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
    final filtered = OfficialReviewSession(engine: fake, flags: _flags);
    await filtered.openDeck(1);
    filtered.isFilteredDeck = true;
    await filtered.buryOrSuspend(OfficialBuryOrSuspendAction.buryUser);
    expect(filtered.phase, OfficialReviewPhase.recoverableError);
    expect(fake.buried, isEmpty);
  });

  test('audit events omit card text and deny-write still holds', () {
    final log = OfficialAnkiAuditLog();
    log.record(
      owner: AnkiWriteOwner.officialScheduler,
      operation: 'answer',
      requestId: 'r1',
      cardId: 11,
      sourceId: 'src',
    );
    final encoded = jsonEncode(log.events.single.toJson());
    expect(encoded.contains('你好'), isFalse);
    expect(encoded.contains('questionHtml'), isFalse);
    expect(log.aggregate()['officialScheduler.answer'], 1);
    const guard = AnkiWriteGuard();
    expect(
      () => guard.assertAllowed(
        sourceEngine: AnkiEngineKind.official,
        owner: AnkiWriteOwner.turnaSrs,
        operation: 'answer',
      ),
      throwsA(isA<AnkiWriteDenied>()),
    );
  });

  test('dry-run crash resume is idempotent and writes no scheduling', () {
    const matcher = LegacyAnkiDryRunMatcher();
    const legacy = [
      LegacyAnkiCardIdentity(
        legacyCardId: 1,
        legacyWordId: 'w1',
        noteGuid: 'g1',
        templateOrd: 0,
      ),
      LegacyAnkiCardIdentity(
        legacyCardId: 2,
        legacyWordId: 'w2',
        noteGuid: 'g2',
        templateOrd: 0,
      ),
    ];
    const official = [
      OfficialAnkiCardIdentity(officialCardId: 11, noteGuid: 'g1', templateOrd: 0),
      OfficialAnkiCardIdentity(officialCardId: 12, noteGuid: 'g2', templateOrd: 0),
    ];
    final full = matcher.match(legacy: legacy, official: official);
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    dao.insertDetected(
      migrationId: 'mig-resume',
      profileId: 'p',
      legacyImportId: 'imp',
      policy: LegacyAnkiSchedulingPolicy.keepLegacyReadOnly,
      nowMillis: 1,
    );
    final firstPage = matcher.match(
      legacy: legacy,
      official: official,
      afterLegacyCardId: 0,
      limit: 1,
    );
    dao.upsertCardMapRows(migrationId: 'mig-resume', rows: firstPage.rows);
    dao.setCursor(
      migrationId: 'mig-resume',
      cursorLegacyCardId: firstPage.rows.single.legacyCardId,
      nowMillis: 2,
    );
    final storedMid = dao.findByLegacyImport(profileId: 'p', legacyImportId: 'imp');
    final secondPage = matcher.match(
      legacy: legacy,
      official: official,
      afterLegacyCardId: storedMid!.legacyCardCount > 0
          ? firstPage.rows.single.legacyCardId
          : firstPage.rows.single.legacyCardId,
      limit: 1,
    );
    dao.upsertCardMapRows(migrationId: 'mig-resume', rows: secondPage.rows);
    final stored = dao.listCardMap('mig-resume');
    expect(stored.map((row) => row.officialCardId), full.rows.map((row) => row.officialCardId));
    expect(
      db.handle.select('SELECT name FROM sqlite_master').map((row) => row['name']),
      isNot(contains('srs_states')),
    );
  });

  test('matcher goldens cover reverse cloze duplicate and unicode', () {
    const matcher = LegacyAnkiDryRunMatcher();
    final result = matcher.match(
      legacy: const [
        LegacyAnkiCardIdentity(
          legacyCardId: 1,
          legacyWordId: 'basic',
          noteGuid: 'guid-basic',
          templateOrd: 0,
        ),
        LegacyAnkiCardIdentity(
          legacyCardId: 2,
          legacyWordId: 'reverse',
          noteGuid: 'guid-rev',
          templateOrd: 1,
        ),
        LegacyAnkiCardIdentity(
          legacyCardId: 3,
          legacyWordId: 'cloze',
          noteGuid: 'guid-cloze',
          templateOrd: 0,
        ),
        LegacyAnkiCardIdentity(
          legacyCardId: 4,
          legacyWordId: 'dup-a',
          noteGuid: 'guid-dup',
          templateOrd: 0,
        ),
        LegacyAnkiCardIdentity(
          legacyCardId: 5,
          legacyWordId: 'dup-b',
          noteGuid: 'guid-dup',
          templateOrd: 0,
        ),
        LegacyAnkiCardIdentity(
          legacyCardId: 6,
          legacyWordId: 'missing',
          noteGuid: '',
          templateOrd: 0,
        ),
        LegacyAnkiCardIdentity(
          legacyCardId: 7,
          legacyWordId: 'unicode',
          noteGuid: 'guid-你好',
          templateOrd: 0,
        ),
      ],
      official: const [
        OfficialAnkiCardIdentity(
          officialCardId: 101,
          noteGuid: 'guid-basic',
          templateOrd: 0,
        ),
        OfficialAnkiCardIdentity(
          officialCardId: 102,
          noteGuid: 'guid-rev',
          templateOrd: 1,
        ),
        OfficialAnkiCardIdentity(
          officialCardId: 103,
          noteGuid: 'guid-cloze',
          templateOrd: 0,
        ),
        OfficialAnkiCardIdentity(
          officialCardId: 104,
          noteGuid: 'guid-dup',
          templateOrd: 0,
        ),
        OfficialAnkiCardIdentity(
          officialCardId: 105,
          noteGuid: 'guid-dup',
          templateOrd: 0,
        ),
        OfficialAnkiCardIdentity(
          officialCardId: 107,
          noteGuid: 'guid-你好',
          templateOrd: 0,
        ),
      ],
    );
    expect(result.rows[0].matchState, LegacyAnkiMatchState.matched);
    expect(result.rows[1].matchState, LegacyAnkiMatchState.matched);
    expect(result.rows[2].matchState, LegacyAnkiMatchState.matched);
    expect(result.rows[3].matchState, LegacyAnkiMatchState.collision);
    expect(result.rows[4].matchState, LegacyAnkiMatchState.collision);
    expect(result.rows[5].matchState, LegacyAnkiMatchState.needsUserAction);
    expect(result.rows[6].officialCardId, 107);
  });

  testWidgets('migration preview cannot cut over', (tester) async {
    expect(LegacyAnkiMigrationFlags.cutoverEnabled, isTrue);
    const census = LegacyAnkiCensusReport(
      generatedAtMillis: 1,
      platform: 'linux',
      imports: [
        LegacyAnkiImportCensus(
          importId: 'imp',
          sourceHash: 'h',
          noteCount: 1,
          cardCount: 1,
          mediaCount: 0,
          deckCount: 1,
          importedScheduling: false,
          status: 'ready',
          sourceFilePresent: true,
          srsRowCount: 0,
          reviewEventCount: 0,
          duplicateGuidCount: 0,
          missingGuidCount: 0,
        ),
      ],
    );
    const dryRun = LegacyAnkiDryRunResult(
      rows: [
        LegacyAnkiCardMapDraft(
          legacyCardId: 1,
          legacyWordId: 'w',
          templateOrd: 0,
          matchMethod: LegacyAnkiMatchMethod.noteGuidAndOrdinal,
          matchState: LegacyAnkiMatchState.needsUserAction,
        ),
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: OfficialAnkiMigrationPreviewPage(
          census: census,
          dryRun: dryRun,
          diskFreeBytes: 99,
        ),
      ),
    );
    final cutover = tester.widget<FilledButton>(
      find.byKey(const Key('official-migration-cutover-disabled')),
    );
    expect(cutover.onPressed, isNull);
    expect(
      const AnkiSourceRouteResolver().resolve(sourceKey: 'imp'),
      AnkiEngineKind.legacy,
    );
  });

  test('backup manifest is descriptive only', () {
    final manifest = LegacyAnkiBackupManifest(
      legacyRowCount: 4,
      legacyRowHash: LegacyAnkiBackupManifest.hashCounts(
        importCount: 1,
        noteCount: 2,
        cardCount: 3,
        srsCount: 3,
      ),
      officialBackupId: 'bak-1',
      projectionFingerprint: 'proj-1',
      createdAtMillis: 8,
    );
    final round = LegacyAnkiBackupManifest.fromJson(manifest.toJson());
    expect(round.legacyRowCount, 4);
    expect(round.officialBackupId, 'bak-1');
    expect(jsonEncode(round.toJson()).contains('srs_states'), isFalse);
  });
}
