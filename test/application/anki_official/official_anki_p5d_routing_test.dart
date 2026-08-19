import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/anki_review_assembler.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
import 'package:turna/application/anki_official/import/anki_import_facade.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_gray_config.dart';
import 'package:turna/application/anki_official/migration/official_anki_user_allowlist.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/migration/official_anki_review_gate_decision.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/domain/course/srs_word.dart';

void main() {
  test('p5d_default_build_still_routes_legacy', () {
    expect(LegacyAnkiMigrationFlags.cutoverEnabled, isFalse);
    const resolver = AnkiSourceRouteResolver();
    expect(
      resolver.resolve(
        sourceKey: 'p5c-fixture-device',
        recordedKind: AnkiEngineKind.official,
        officialCatalogHasSource: true,
      ),
      AnkiEngineKind.legacy,
    );
    expect(
      AnkiImportFacade.decisionFor(const OfficialAnkiFeatureFlags(
        engine: true,
        import: true,
        catalogReady: true,
        runtimeCapable: true,
        platformReady: true,
      )),
      AnkiImportDecision.legacy,
    );
  });

  test('p5d_cutover_and_recordedKind_official_routes_official', () {
    const resolver = AnkiSourceRouteResolver();
    expect(
      resolver.resolve(
        sourceKey: 'p5c-fixture-device',
        recordedKind: AnkiEngineKind.official,
        cutoverEnabled: true,
      ),
      AnkiEngineKind.official,
    );
    expect(
      AnkiImportFacade.decisionFor(
        const OfficialAnkiFeatureFlags(
          engine: true,
          import: true,
          catalogReady: true,
          runtimeCapable: true,
          platformReady: true,
        ),
        cutoverEnabled: true,
        platform: 'android',
        gray: const OfficialAnkiGrayConfig(cohort: OfficialAnkiGrayCohort.g1),
      ),
      AnkiImportDecision.official,
    );
  });

  test('p5d_user_deck_without_recordedKind_stays_legacy', () {
    const resolver = AnkiSourceRouteResolver();
    expect(
      resolver.resolve(
        sourceKey: 'user-deck',
        recordedKind: null,
        officialCatalogHasSource: false,
        cutoverEnabled: true,
      ),
      AnkiEngineKind.legacy,
    );
  });

  test('p5d_ohos_import_stays_legacy', () {
    expect(
      AnkiImportFacade.decisionFor(
        const OfficialAnkiFeatureFlags(
          engine: true,
          import: true,
          catalogReady: true,
          runtimeCapable: true,
          platformReady: true,
        ),
        cutoverEnabled: true,
        platform: 'ohos',
      ),
      AnkiImportDecision.legacy,
    );
  });

  test('p5d_due_does_not_double_count_official_source', () {
    OfficialAnkiHomeDue.reset();
    OfficialAnkiHomeDue.officialImportIds = {'p5c-fixture-device'};
    OfficialAnkiHomeDue.officialDue = 3;
    final words = [
      SrsWord(
        wordId: 'anki-p5c-fixture-device-c1375933503610',
        dueAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      SrsWord(
        wordId: 'anki-user-deck-c1',
        dueAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      SrsWord(
        wordId: 'not-anki',
        dueAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ];
    expect(OfficialAnkiHomeDue.legacyAnkiDueExcludingOfficial(words), 1);
    expect(OfficialAnkiHomeDue.aggregatedAnkiDue(words), 4);
  });

  test('p5d production router lists official import ids only when cutover on',
      () {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    dao.insertDetected(
      migrationId: 'mig-p5c-fixture-device',
      profileId: 'profile-default-01',
      legacyImportId: 'p5c-fixture-device',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    dao.setRecordedKind(
      migrationId: 'mig-p5c-fixture-device',
      recordedKind: 'official',
      nowMillis: 2,
    );
    const router = OfficialAnkiProductionRouter();
    expect(
      router.officialImportIds(dao: dao, cutoverEnabled: false),
      isEmpty,
    );
    expect(
      router.officialImportIds(dao: dao, cutoverEnabled: true),
      {'p5c-fixture-device'},
    );
  });

  test('p5d refreshHomeDue sums official decks once', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    OfficialAnkiSourceDao(db).upsertSource(
      sourceId: 'src-fe08',
      profileId: 'profile-default-01',
      sourceHash: '28d89bb7',
      sourceSize: 1,
      displayName: 'p5c-fixture',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    db.handle.execute(
      'INSERT INTO anki_source_cards '
      '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
      "VALUES ('src-fe08', 1375933503610, 1, 1, 'g', 0)",
    );
    final dao = OfficialAnkiMigrationDao(db);
    dao.insertDetected(
      migrationId: 'mig-p5c-fixture-device',
      profileId: 'profile-default-01',
      legacyImportId: 'p5c-fixture-device',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    dao.transition(
      migrationId: 'mig-p5c-fixture-device',
      expected: LegacyAnkiMigrationState.detected,
      next: LegacyAnkiMigrationState.awaitingPackage,
      nowMillis: 2,
      officialSourceId: 'src-fe08',
    );
    dao.setRecordedKind(
      migrationId: 'mig-p5c-fixture-device',
      recordedKind: 'official',
      nowMillis: 3,
    );
    OfficialAnkiHomeDue.reset();
    final total = await const OfficialAnkiProductionRouter().refreshHomeDue(
      dao: dao,
      sources: OfficialAnkiSourceDao(db),
      cutoverEnabled: true,
      countsForDeck: (deckId) async => OfficialDeckCounts(
        deckId: deckId,
        newCount: 1,
        reviewCount: 2,
      ),
    );
    expect(total, 3);
    expect(OfficialAnkiHomeDue.officialDue, 3);
    expect(
      OfficialAnkiHomeDue.officialDueByImport['p5c-fixture-device'],
      3,
    );
  });

  test('p5d official review gate fail-closed when target missing', () {
    expect(
      decideOfficialReviewGate(
        cutoverEnabled: false,
        routedEngine: AnkiEngineKind.official,
        catalogPresent: true,
        hasReviewTarget: true,
        canOpenOfficialReview: true,
      ),
      OfficialAnkiReviewGateDecision.useLegacy,
    );
    expect(
      decideOfficialReviewGate(
        cutoverEnabled: true,
        routedEngine: AnkiEngineKind.legacy,
        catalogPresent: true,
        hasReviewTarget: false,
        canOpenOfficialReview: true,
      ),
      OfficialAnkiReviewGateDecision.useLegacy,
    );
    expect(
      decideOfficialReviewGate(
        cutoverEnabled: true,
        routedEngine: AnkiEngineKind.official,
        catalogPresent: true,
        hasReviewTarget: false,
        canOpenOfficialReview: true,
      ),
      OfficialAnkiReviewGateDecision.failClosed,
    );
    expect(
      decideOfficialReviewGate(
        cutoverEnabled: true,
        routedEngine: AnkiEngineKind.official,
        catalogPresent: false,
        hasReviewTarget: true,
        canOpenOfficialReview: true,
      ),
      OfficialAnkiReviewGateDecision.failClosed,
    );
    expect(
      decideOfficialReviewGate(
        cutoverEnabled: true,
        routedEngine: AnkiEngineKind.official,
        catalogPresent: true,
        hasReviewTarget: true,
        canOpenOfficialReview: false,
      ),
      OfficialAnkiReviewGateDecision.failClosed,
    );
    expect(
      decideOfficialReviewGate(
        cutoverEnabled: true,
        routedEngine: AnkiEngineKind.official,
        catalogPresent: true,
        hasReviewTarget: true,
        canOpenOfficialReview: true,
      ),
      OfficialAnkiReviewGateDecision.openOfficial,
    );
  });

  test('p5d importIdFromWordId matches assembler prefix', () {
    expect(
      AnkiReviewAssembler.importIdFromWordId('anki-p5c-fixture-device-c1'),
      'p5c-fixture-device',
    );
  });

  test('p5d_official_due_nonzero_when_review_card_due', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    OfficialAnkiSourceDao(db).upsertSource(
      sourceId: 'src-due-nonzero',
      profileId: 'profile-default-01',
      sourceHash: '28d89bb7',
      sourceSize: 1,
      displayName: 'p5c-fixture',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    db.handle.execute(
      'INSERT INTO anki_source_cards '
      '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
      "VALUES ('src-due-nonzero', 1375933503610, 1, 11, 'g', 0)",
    );
    final dao = OfficialAnkiMigrationDao(db);
    dao.insertDetected(
      migrationId: 'mig-p5c-fixture-nonzero',
      profileId: 'profile-default-01',
      legacyImportId: 'p5c-fixture-device',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    dao.transition(
      migrationId: 'mig-p5c-fixture-nonzero',
      expected: LegacyAnkiMigrationState.detected,
      next: LegacyAnkiMigrationState.awaitingPackage,
      nowMillis: 2,
      officialSourceId: 'src-due-nonzero',
    );
    dao.setRecordedKind(
      migrationId: 'mig-p5c-fixture-nonzero',
      recordedKind: 'official',
      nowMillis: 3,
    );
    OfficialAnkiHomeDue.reset();
    final total = await const OfficialAnkiProductionRouter().refreshHomeDueFromQueue(
      dao: dao,
      sources: OfficialAnkiSourceDao(db),
      cutoverEnabled: true,
      getReviewQueue: () async => OfficialReviewQueue(
        sessionId: 's1',
        queueEpoch: 1,
        newCount: 1,
        learningCount: 1,
        reviewCount: 1,
        cards: const [
          OfficialReviewQueueCard(
            cardId: 1375933503610,
            noteId: 1,
            deckId: 11,
            templateOrdinal: 0,
            queueKind: 'review',
            answerToken: 'tok-1',
            labels: OfficialReviewIntervalLabels(
              again: '10m',
              hard: '1d',
              good: '3d',
              easy: '7d',
            ),
          ),
        ],
      ),
    );
    expect(total, 3);
    expect(OfficialAnkiHomeDue.officialDue, 3);
    expect(OfficialAnkiHomeDue.officialDueUnavailable, isFalse);
  });

  test('p5d_official_due_zero_when_only_future_review', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    OfficialAnkiSourceDao(db).upsertSource(
      sourceId: 'src-future',
      profileId: 'profile-default-01',
      sourceHash: '28d89bb7',
      sourceSize: 1,
      displayName: 'p5c-fixture',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    db.handle.execute(
      'INSERT INTO anki_source_cards '
      '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
      "VALUES ('src-future', 1375933503611, 1, 12, 'g', 0)",
    );
    final dao = OfficialAnkiMigrationDao(db);
    dao.insertDetected(
      migrationId: 'mig-p5c-fixture-future',
      profileId: 'profile-default-01',
      legacyImportId: 'p5c-fixture-device',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    dao.transition(
      migrationId: 'mig-p5c-fixture-future',
      expected: LegacyAnkiMigrationState.detected,
      next: LegacyAnkiMigrationState.awaitingPackage,
      nowMillis: 2,
      officialSourceId: 'src-future',
    );
    dao.setRecordedKind(
      migrationId: 'mig-p5c-fixture-future',
      recordedKind: 'official',
      nowMillis: 3,
    );
    OfficialAnkiHomeDue.reset();
    final total = await const OfficialAnkiProductionRouter().refreshHomeDueFromQueue(
      dao: dao,
      sources: OfficialAnkiSourceDao(db),
      cutoverEnabled: true,
      getReviewQueue: () async => OfficialReviewQueue(
        sessionId: 's1',
        queueEpoch: 1,
        newCount: 0,
        learningCount: 0,
        reviewCount: 0,
        cards: const [],
      ),
    );
    expect(total, 0);
    expect(OfficialAnkiHomeDue.officialDue, 0);
    expect(OfficialAnkiHomeDue.officialDueUnavailable, isFalse);
  });

  test('p5d_due_refresh_does_not_treat_lock_as_zero', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    OfficialAnkiSourceDao(db).upsertSource(
      sourceId: 'src-lock',
      profileId: 'profile-default-01',
      sourceHash: '28d89bb7',
      sourceSize: 1,
      displayName: 'p5c-fixture',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    db.handle.execute(
      'INSERT INTO anki_source_cards '
      '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
      "VALUES ('src-lock', 1375933503612, 1, 13, 'g', 0)",
    );
    final dao = OfficialAnkiMigrationDao(db);
    dao.insertDetected(
      migrationId: 'mig-p5c-fixture-lock',
      profileId: 'profile-default-01',
      legacyImportId: 'p5c-fixture-device',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    dao.transition(
      migrationId: 'mig-p5c-fixture-lock',
      expected: LegacyAnkiMigrationState.detected,
      next: LegacyAnkiMigrationState.awaitingPackage,
      nowMillis: 2,
      officialSourceId: 'src-lock',
    );
    dao.setRecordedKind(
      migrationId: 'mig-p5c-fixture-lock',
      recordedKind: 'official',
      nowMillis: 3,
    );
    OfficialAnkiHomeDue.reset();
    OfficialAnkiHomeDue.officialDue = 4;
    OfficialAnkiHomeDue.officialDueByImport = {'p5c-fixture-device': 4};
    OfficialAnkiHomeDue.officialImportIds = {'p5c-fixture-device'};
    OfficialAnkiHomeDue.officialDueUnavailable = false;
    try {
      await const OfficialAnkiProductionRouter().refreshHomeDueFromQueue(
        dao: dao,
        sources: OfficialAnkiSourceDao(db),
        cutoverEnabled: true,
        getReviewQueue: () async => throw const OfficialAnkiException(
          code: OfficialAnkiErrorCode.collectionLocked,
          messageKey: 'official_anki.collection_locked',
        ),
      );
      fail('expected collectionLocked');
    } on OfficialAnkiException catch (error) {
      expect(error.code, OfficialAnkiErrorCode.collectionLocked);
    }
    expect(OfficialAnkiHomeDue.officialDue, 4);
    expect(OfficialAnkiHomeDue.officialDueUnavailable, isFalse);
    final total = await const OfficialAnkiProductionRouter().refreshHomeDue(
      dao: dao,
      sources: OfficialAnkiSourceDao(db),
      cutoverEnabled: true,
      countsForDeck: (deckId) async => OfficialDeckCounts(
        deckId: deckId,
        newCount: 0,
        reviewCount: 0,
      ),
    );
    expect(total, 0);
    expect(OfficialAnkiHomeDue.officialDueUnavailable, isFalse);
  });

  test('p5d_start_review_pushes_official_page_when_cutover_official', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    OfficialAnkiSourceDao(db).upsertSource(
      sourceId: 'src-gate-official',
      profileId: 'profile-default-01',
      sourceHash: '28d89bb7',
      sourceSize: 1,
      displayName: 'p5c-fixture',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    db.handle.execute(
      'INSERT INTO anki_source_cards '
      '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
      "VALUES ('src-gate-official', 1375933503613, 1, 21, 'g', 0)",
    );
    final dao = OfficialAnkiMigrationDao(db);
    dao.insertDetected(
      migrationId: 'mig-p5c-fixture-gate',
      profileId: 'profile-default-01',
      legacyImportId: 'p5c-fixture-device',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    dao.transition(
      migrationId: 'mig-p5c-fixture-gate',
      expected: LegacyAnkiMigrationState.detected,
      next: LegacyAnkiMigrationState.awaitingPackage,
      nowMillis: 2,
      officialSourceId: 'src-gate-official',
    );
    dao.setRecordedKind(
      migrationId: 'mig-p5c-fixture-gate',
      recordedKind: 'official',
      nowMillis: 3,
    );
    expect(
      const OfficialAnkiProductionRouter().engineForImport(
        importId: 'p5c-fixture-device',
        dao: dao,
        cutoverEnabled: true,
      ),
      AnkiEngineKind.official,
    );
    expect(
      const OfficialAnkiProductionRouter()
          .reviewTargetForImport(
            dao: dao,
            sources: OfficialAnkiSourceDao(db),
            importId: 'p5c-fixture-device',
            cutoverEnabled: true,
          )!
          .deckId,
      21,
    );
    expect(
      decideOfficialReviewGate(
        cutoverEnabled: true,
        routedEngine: AnkiEngineKind.official,
        catalogPresent: true,
        hasReviewTarget: true,
        canOpenOfficialReview: true,
      ),
      OfficialAnkiReviewGateDecision.openOfficial,
    );
  });

  test('p5d_start_review_fail_closed_does_not_push_legacy_session', () {
    expect(
      decideOfficialReviewGate(
        cutoverEnabled: true,
        routedEngine: AnkiEngineKind.official,
        catalogPresent: true,
        hasReviewTarget: false,
        canOpenOfficialReview: true,
      ),
      OfficialAnkiReviewGateDecision.failClosed,
    );
    expect(
      decideOfficialReviewGate(
        cutoverEnabled: true,
        routedEngine: AnkiEngineKind.official,
        catalogPresent: true,
        hasReviewTarget: true,
        canOpenOfficialReview: false,
      ),
      OfficialAnkiReviewGateDecision.failClosed,
    );
  });

  test('p5d_gray_default_cohort_is_off', () {
    expect(OfficialAnkiGrayConfig.fromEnvironment().cohort, OfficialAnkiGrayCohort.off);
    expect(OfficialAnkiGrayConfig.fromEnvironment().isOn, isFalse);
    expect(
      const OfficialAnkiGrayConfig(cohort: OfficialAnkiGrayCohort.off).isOn,
      isFalse,
    );
    expect(
      const OfficialAnkiGrayConfig(cohort: OfficialAnkiGrayCohort.off).thresholdPercent,
      0,
    );
    expect(
      const OfficialAnkiGrayConfig(cohort: OfficialAnkiGrayCohort.g1).thresholdPercent,
      1,
    );
    expect(
      const OfficialAnkiGrayConfig(cohort: OfficialAnkiGrayCohort.off)
          .allowsNewOfficialImport(platform: 'android', cutoverEnabled: true),
      isFalse,
    );
    expect(
      const OfficialAnkiGrayConfig(cohort: OfficialAnkiGrayCohort.g1)
          .allowsNewOfficialImport(platform: 'android', cutoverEnabled: true),
      isTrue,
    );
    expect(
      AnkiImportFacade.decisionFor(
        const OfficialAnkiFeatureFlags(
          engine: true,
          import: true,
          catalogReady: true,
          runtimeCapable: true,
          platformReady: true,
        ),
        cutoverEnabled: true,
        platform: 'android',
        gray: const OfficialAnkiGrayConfig(cohort: OfficialAnkiGrayCohort.off),
      ),
      AnkiImportDecision.legacy,
    );
  });

  test('preview_cutover_button_stays_disabled', () {
    final source = File(
      'lib/views/anki_official/official_anki_migration_preview_page.dart',
    ).readAsStringSync();
    expect(source.contains('Cutover (disabled)'), isTrue);
    expect(source.contains('official-migration-cutover-disabled'), isTrue);
    expect(source.contains('onPressed: null'), isTrue);
  });

  test('p5d_gray_g_cohort_thresholds_are_sequential', () {
    expect(const OfficialAnkiGrayConfig(cohort: OfficialAnkiGrayCohort.g2).thresholdPercent, 10);
    expect(const OfficialAnkiGrayConfig(cohort: OfficialAnkiGrayCohort.g3).thresholdPercent, 50);
    expect(const OfficialAnkiGrayConfig(cohort: OfficialAnkiGrayCohort.g4).thresholdPercent, 100);
    expect(OfficialAnkiGrayConfig.parseGrayCohort('g2'), OfficialAnkiGrayCohort.g2);
    expect(OfficialAnkiGrayConfig.parseGrayCohort('10%'), OfficialAnkiGrayCohort.g2);
  });

  test('p5d_gray_import_requires_cutover_and_android', () {
    expect(
      AnkiImportFacade.decisionFor(
        const OfficialAnkiFeatureFlags(
          engine: true,
          import: true,
          catalogReady: true,
          runtimeCapable: true,
          platformReady: true,
        ),
        cutoverEnabled: false,
        platform: 'android',
        gray: const OfficialAnkiGrayConfig(cohort: OfficialAnkiGrayCohort.g4),
      ),
      AnkiImportDecision.legacy,
    );
    expect(
      AnkiImportFacade.decisionFor(
        const OfficialAnkiFeatureFlags(
          engine: true,
          import: true,
          catalogReady: true,
          runtimeCapable: true,
          platformReady: true,
        ),
        cutoverEnabled: true,
        platform: 'ohos',
        gray: const OfficialAnkiGrayConfig(cohort: OfficialAnkiGrayCohort.g4),
      ),
      AnkiImportDecision.legacy,
    );
  });

  test('ankiweb_not_linked_from_production_routes', () {
    final routing = File('lib/routing/routing.dart').readAsStringSync();
    final review = File('lib/views/anki/anki_review_screen.dart').readAsStringSync();
    expect(routing.toLowerCase().contains('ankiweb'), isFalse);
    expect(review.toLowerCase().contains('ankiweb'), isFalse);
    final preview = File(
      'lib/views/anki_official/official_anki_migration_preview_page.dart',
    ).readAsStringSync();
    expect(preview.toLowerCase().contains('ankiweb'), isFalse);
    expect(
      File(
        'lib/application/anki_official/migration/official_anki_gray_config.dart',
      ).readAsStringSync().toLowerCase().contains('ankiweb'),
      isFalse,
    );
    expect(
      File(
        'lib/application/anki_official/migration/official_anki_user_allowlist.dart',
      ).readAsStringSync().toLowerCase().contains('ankiweb'),
      isFalse,
    );
  });

  test('p5d_user_allowlist_is_per_source_hash_and_rejects_bulk', () {
    expect(isUserAllowlistedSource(importId: 'p5c-fixture-device'), isTrue);
    expect(isUserAllowlistedSource(sourceHash: '28d89bb7bf41df25513e148e96acbdac93bcc71fadcee8e552b57d4413394d02'), isTrue);
    expect(isUserAllowlistedSource(importId: 'user-deck', sourceHash: 'deadbeef'), isFalse);
    expect(isUserAllowlistedSource(importId: 'user-deck'), isFalse);
  });

  test('p5d_gray_config_does_not_import_coursedatabase_or_census', () {
    final src = File(
      'lib/application/anki_official/migration/official_anki_gray_config.dart',
    ).readAsStringSync();
    expect(src.toLowerCase().contains('coursedatabase'), isFalse);
    expect(src.toLowerCase().contains('census'), isFalse);
    final allowSrc = File(
      'lib/application/anki_official/migration/official_anki_user_allowlist.dart',
    ).readAsStringSync();
    expect(allowSrc.toLowerCase().contains('coursedatabase'), isFalse);
  });
}
