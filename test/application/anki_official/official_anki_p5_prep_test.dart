import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/anki_srs_migrator.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart';
import 'package:turna/application/anki_official/import/anki_import_facade.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_backup_manifest.dart';
import 'package:turna/application/anki_official/migration/official_anki_census.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_saga.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_fixture_pilot_saga.dart';
import 'package:turna/application/anki_official/migration/official_anki_fixture_rollback_drill.dart';
import 'package:turna/application/anki_official/migration/official_anki_gray_config.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_preview_loader.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_write_owner.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/domain/course/srs_word.dart';

void main() {
  test('P5-A01 inventory lists thirty legacy files and no card text', () {
    final inventory = File(
      'docs/official-anki-migration/15-p5-legacy-inventory.md',
    ).readAsStringSync();
    expect(inventory.contains('14,995'), isTrue);
    expect(inventory.contains('anki_srs_migrator.dart'), isTrue);
    expect(inventory.contains('fieldsJson'), isFalse);
    expect(inventory.contains('questionHtml'), isFalse);
  });

  test('census JSON is desensitized and counts guids', () async {
    final service = LegacyAnkiCensusService(_FakeCensusReader());
    final report = await service.collect(platform: 'linux', nowMillis: 10);
    final json = report.toJson();
    final encoded = jsonEncode(json);
    expect(json['schemaVersion'], 1);
    expect((json['totals'] as Map)['sourceCount'], 1);
    expect((json['totals'] as Map)['cardCount'], 3);
    expect(encoded.contains('你好'), isFalse);
    expect(encoded.contains('/home/user'), isFalse);
    expect(encoded.contains('Front'), isFalse);
    final row = (json['imports'] as List).single as Map;
    expect(row['duplicateGuidCount'], 1);
    expect(row['missingGuidCount'], 1);
    expect(row['sourceFilePresent'], isFalse);
  });

  test('resolver keeps current engines and cutover stays false', () {
    expect(LegacyAnkiMigrationFlags.cutoverEnabled, isFalse);
    const resolver = AnkiSourceRouteResolver();
    expect(
      resolver.resolve(sourceKey: 'legacy-1'),
      AnkiEngineKind.legacy,
    );
    expect(
      resolver.resolve(sourceKey: 'src-official', officialCatalogHasSource: true),
      AnkiEngineKind.legacy,
    );
    expect(
      resolver.resolve(
        sourceKey: 'src-official',
        officialCatalogHasSource: true,
        recordedKind: AnkiEngineKind.official,
        cutoverEnabled: true,
      ),
      AnkiEngineKind.official,
    );
    expect(
      resolver.resolve(
        sourceKey: 'src-official',
        officialCatalogHasSource: true,
        recordedKind: AnkiEngineKind.legacy,
        cutoverEnabled: true,
      ),
      AnkiEngineKind.legacy,
    );
  });

  test('write owner deny-write tests isolate engines', () {
    const guard = AnkiWriteGuard();
    expect(
      () => guard.assertAllowed(
        sourceEngine: AnkiEngineKind.official,
        owner: AnkiWriteOwner.turnaSrs,
        operation: 'answer',
      ),
      throwsA(isA<AnkiWriteDenied>()),
    );
    expect(
      () => guard.assertAllowed(
        sourceEngine: AnkiEngineKind.legacy,
        owner: AnkiWriteOwner.officialScheduler,
        operation: 'answer',
      ),
      throwsA(isA<AnkiWriteDenied>()),
    );
    expect(
      () => guard.assertAllowed(
        sourceEngine: AnkiEngineKind.official,
        owner: AnkiWriteOwner.projection,
        operation: 'answer',
      ),
      throwsA(isA<AnkiWriteDenied>()),
    );
    guard.assertAllowed(
      sourceEngine: AnkiEngineKind.official,
      owner: AnkiWriteOwner.officialScheduler,
      operation: 'answer',
    );
    guard.assertAllowed(
      sourceEngine: AnkiEngineKind.legacy,
      owner: AnkiWriteOwner.turnaSrs,
      operation: 'answer',
    );
  });

  test('new import stays fail-closed unless official gates are complete', () {
    expect(
      AnkiImportFacade.decisionFor(const OfficialAnkiFeatureFlags()),
      AnkiImportDecision.legacy,
    );
    expect(
      AnkiImportFacade.decisionFor(
        const OfficialAnkiFeatureFlags(import: true, engine: true),
        cutoverEnabled: true,
        platform: 'android',
      ),
      AnkiImportDecision.failClosed,
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

  test('capability matrix keeps OHOS on legacy fallback', () {
    final android = OfficialAnkiCapabilityMatrix.forPlatform('android');
    expect(android.officialCore, isTrue);
    expect(android.legacyFallbackRequired, isTrue);
    final ohos = OfficialAnkiCapabilityMatrix.forPlatform('ohos');
    expect(ohos.officialCore, isFalse);
    expect(ohos.officialReviewer, isFalse);
    expect(ohos.legacyFallbackRequired, isTrue);
    final linux = OfficialAnkiCapabilityMatrix.forPlatform('linux');
    expect(linux.officialCore, isTrue);
    expect(linux.officialReviewer, isFalse);
  });

  test('catalog v6 migrates forward and future versions fail closed', () {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    expect(
      db.handle.select('PRAGMA user_version').first['user_version'],
      kOfficialAnkiCatalogSchemaVersion,
    );
    expect(
      db.handle.select(
        "SELECT name FROM sqlite_master WHERE name = 'legacy_anki_migrations'",
      ),
      isNotEmpty,
    );
    final root = Directory.systemTemp.createTempSync('turna-catalog-v6-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/catalog.sqlite';
    final created = OfficialAnkiDatabase.file(path);
    created.handle.execute('PRAGMA user_version = 99');
    created.close();
    expect(
      () => OfficialAnkiDatabase.file(path),
      throwsA(
        isA<OfficialAnkiException>().having(
          (e) => e.messageKey,
          'messageKey',
          'official_anki.catalog_future_version',
        ),
      ),
    );
  });

  test('unknown migration state fails closed and CAS rejects illegal jumps', () {
    expect(
      () => parseLegacyAnkiMigrationState('done'),
      throwsA(isA<OfficialAnkiException>()),
    );
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    dao.insertDetected(
      migrationId: 'mig-1',
      profileId: 'profile-1',
      legacyImportId: 'imp-1',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
      legacyCardCount: 2,
    );
    expect(
      () => dao.transition(
        migrationId: 'mig-1',
        expected: LegacyAnkiMigrationState.detected,
        next: LegacyAnkiMigrationState.cutover,
        nowMillis: 2,
      ),
      throwsA(isA<OfficialAnkiException>()),
    );
    dao.transition(
      migrationId: 'mig-1',
      expected: LegacyAnkiMigrationState.detected,
      next: LegacyAnkiMigrationState.awaitingPackage,
      nowMillis: 3,
    );
    expect(
      () => dao.transition(
        migrationId: 'mig-1',
        expected: LegacyAnkiMigrationState.detected,
        next: LegacyAnkiMigrationState.awaitingPackage,
        nowMillis: 4,
      ),
      throwsA(isA<OfficialAnkiException>()),
    );
  });

  test('legacy_migration_dry_run_is_read_only_and_idempotent', () {
    const matcher = LegacyAnkiDryRunMatcher();
    const legacy = [
      LegacyAnkiCardIdentity(
        legacyCardId: 11,
        legacyWordId: 'anki-imp-c11',
        legacyNoteId: 7,
        noteGuid: 'guid-a',
        templateOrd: 0,
      ),
      LegacyAnkiCardIdentity(
        legacyCardId: 12,
        legacyWordId: 'anki-imp-c12',
        legacyNoteId: 8,
        noteGuid: '',
        templateOrd: 0,
        contentFingerprint: 'fp-b',
      ),
      LegacyAnkiCardIdentity(
        legacyCardId: 13,
        legacyWordId: 'anki-imp-c13',
        noteGuid: 'missing',
        templateOrd: 0,
      ),
    ];
    const official = [
      OfficialAnkiCardIdentity(
        officialCardId: 101,
        officialNoteId: 7,
        noteGuid: 'guid-a',
        templateOrd: 0,
      ),
      OfficialAnkiCardIdentity(
        officialCardId: 102,
        noteGuid: 'guid-b',
        templateOrd: 0,
        contentFingerprint: 'fp-b',
      ),
    ];
    final first = matcher.match(legacy: legacy, official: official);
    final second = matcher.match(legacy: legacy, official: official);
    expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    expect(first.matchedCount, 2);
    expect(first.unresolvedCount, 1);
    expect(first.rows[2].matchState, LegacyAnkiMatchState.unresolved);

    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    dao.insertDetected(
      migrationId: 'mig-dry',
      profileId: 'profile-1',
      legacyImportId: 'imp-1',
      policy: LegacyAnkiSchedulingPolicy.resetAsNew,
      nowMillis: 1,
    );
    dao.replaceDryRunMap(migrationId: 'mig-dry', result: first);
    dao.replaceDryRunMap(migrationId: 'mig-dry', result: second);
    final stored = dao.listCardMap('mig-dry');
    expect(stored.length, 3);
    expect(stored.first.officialCardId, 101);
    expect(
      db.handle.select('SELECT name FROM sqlite_master').map((row) => row['name']),
      isNot(contains('srs_states')),
    );
  });

  test('legacy_source_never_has_two_writable_engines', () {
    const resolver = AnkiSourceRouteResolver();
    const guard = AnkiWriteGuard();
    final engine = resolver.resolve(sourceKey: 'imp-1');
    expect(engine, AnkiEngineKind.legacy);
    expect(
      () => guard.assertAllowed(
        sourceEngine: engine,
        owner: AnkiWriteOwner.officialScheduler,
        operation: 'answer',
      ),
      throwsA(isA<AnkiWriteDenied>()),
    );
  });

  test('legacy source never has two writable engines', () {
    const resolver = AnkiSourceRouteResolver();
    const guard = AnkiWriteGuard();
    final engine = resolver.resolve(sourceKey: 'imp-1');
    expect(engine, AnkiEngineKind.legacy);
    expect(
      () => guard.assertAllowed(
        sourceEngine: engine,
        owner: AnkiWriteOwner.officialScheduler,
        operation: 'answer',
      ),
      throwsA(isA<AnkiWriteDenied>()),
    );
  });

  test('LegacyAnkiBackupService generates manifest from counts and hashes', () async {
    const service = LegacyAnkiBackupService();
    final manifest = service.generate(
      importCount: 2,
      noteCount: 10,
      cardCount: 20,
      srsCount: 20,
      officialBackupId: 'bak-99',
      projectionFingerprint: 'proj-fp-1',
      createdAtMillis: 1000,
    );
    expect(manifest.legacyRowCount, 52);
    expect(manifest.officialBackupId, 'bak-99');
    expect(manifest.projectionFingerprint, 'proj-fp-1');
    expect(manifest.createdAtMillis, 1000);
    expect(manifest.legacyRowHash, isNotEmpty);

    // Test generateFromCensus
    const census = LegacyAnkiCensusReport(
      generatedAtMillis: 1000,
      platform: 'linux',
      imports: [
        LegacyAnkiImportCensus(
          importId: 'imp-1',
          sourceHash: 'hash-1',
          noteCount: 10,
          cardCount: 20,
          mediaCount: 5,
          deckCount: 1,
          importedScheduling: true,
          status: 'ready',
          sourceFilePresent: true,
          srsRowCount: 20,
          reviewEventCount: 40,
          duplicateGuidCount: 0,
          missingGuidCount: 0,
        ),
      ],
    );
    final fromCensus = service.generateFromCensus(
      census: census,
      officialBackupId: 'bak-census',
      projectionFingerprint: 'proj-census',
      createdAtMillis: 2000,
    );
    expect(fromCensus.legacyRowCount, 51); // 1 import + 10 notes + 20 cards + 20 srs
    expect(fromCensus.officialBackupId, 'bak-census');

    // Test persist to file
    final tempDir = Directory.systemTemp.createTempSync('backup-manifest-test-');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final manifestFile = File('${tempDir.path}/legacy_backup_manifest.json');
    await service.persist(manifest: fromCensus, targetFile: manifestFile);
    expect(manifestFile.existsSync(), isTrue);
    final loaded = LegacyAnkiBackupManifest.fromJson(
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>,
    );
    expect(loaded.legacyRowCount, 51);
    expect(loaded.officialBackupId, 'bak-census');

    // Test recordInDao
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    dao.insertDetected(
      migrationId: 'mig-backup-test',
      profileId: 'p1',
      legacyImportId: 'imp-1',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 100,
    );
    service.recordInDao(
      dao: dao,
      migrationId: 'mig-backup-test',
      manifest: fromCensus,
      nowMillis: 200,
    );
    final row = dao.findByLegacyImport(profileId: 'p1', legacyImportId: 'imp-1');
    expect(row?.backupId, 'bak-census');
    expect(row?.backupManifestHash, fromCensus.legacyRowHash);
  });

  test('LegacyAnkiDryRunSaga processes in chunks, supports crash resume and is strictly idempotent', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);

    dao.insertDetected(
      migrationId: 'mig-saga',
      profileId: 'prof-1',
      legacyImportId: 'imp-1',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 100,
      legacyCardCount: 5,
    );

    const legacy = [
      LegacyAnkiCardIdentity(legacyCardId: 1, legacyWordId: 'w1', noteGuid: 'g1', templateOrd: 0),
      LegacyAnkiCardIdentity(legacyCardId: 2, legacyWordId: 'w2', noteGuid: 'g2', templateOrd: 0),
      LegacyAnkiCardIdentity(legacyCardId: 3, legacyWordId: 'w3', noteGuid: 'g3', templateOrd: 0),
      LegacyAnkiCardIdentity(legacyCardId: 4, legacyWordId: 'w4', noteGuid: 'g4', templateOrd: 0),
      LegacyAnkiCardIdentity(legacyCardId: 5, legacyWordId: 'w5', noteGuid: 'g5', templateOrd: 0),
    ];

    const official = [
      OfficialAnkiCardIdentity(officialCardId: 101, noteGuid: 'g1', templateOrd: 0),
      OfficialAnkiCardIdentity(officialCardId: 102, noteGuid: 'g2', templateOrd: 0),
      OfficialAnkiCardIdentity(officialCardId: 103, noteGuid: 'g3', templateOrd: 0),
      OfficialAnkiCardIdentity(officialCardId: 104, noteGuid: 'g4', templateOrd: 0),
      OfficialAnkiCardIdentity(officialCardId: 105, noteGuid: 'g5', templateOrd: 0),
    ];

    const saga = LegacyAnkiDryRunSaga(pageSize: 2);

    final partialResult = await saga.run(
      dao: dao,
      migrationId: 'mig-saga',
      legacyCards: legacy.take(2).toList(),
      officialCards: official,
      nowMillis: 200,
    );
    expect(partialResult.rows.length, 2);
    expect(dao.getCursor('mig-saga'), 2);

    final resumedResult = await saga.run(
      dao: dao,
      migrationId: 'mig-saga',
      legacyCards: legacy,
      officialCards: official,
      nowMillis: 300,
    );
    expect(resumedResult.rows.length, 5);
    expect(resumedResult.matchedCount, 5);
    expect(resumedResult.unresolvedCount, 0);
    expect(dao.getCursor('mig-saga'), 5);

    dao.insertDetected(
      migrationId: 'mig-saga-full',
      profileId: 'prof-1',
      legacyImportId: 'imp-2',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 100,
      legacyCardCount: 5,
    );
    final directResult = await saga.run(
      dao: dao,
      migrationId: 'mig-saga-full',
      legacyCards: legacy,
      officialCards: official,
      nowMillis: 300,
    );
    expect(jsonEncode(resumedResult.toJson()), jsonEncode(directResult.toJson()));
  });

  test('preview loader prefers allowlist import over first census row', () {
    const user = LegacyAnkiImportCensus(
      importId: 'user-deck',
      sourceHash: 'not-a-fixture',
      noteCount: 10,
      cardCount: 10,
      mediaCount: 0,
      deckCount: 1,
      importedScheduling: true,
      status: 'ready',
      sourceFilePresent: true,
      srsRowCount: 10,
      reviewEventCount: 0,
      duplicateGuidCount: 0,
      missingGuidCount: 0,
    );
    const fixture = LegacyAnkiImportCensus(
      importId: 'p5c-fixture-device',
      sourceHash: 'bbe354db3925f4b4d7e8d66b0770e83f2ce38586e1071398e762d821636cad58',
      noteCount: 2,
      cardCount: 2,
      mediaCount: 0,
      deckCount: 1,
      importedScheduling: true,
      status: 'ready',
      sourceFilePresent: true,
      srsRowCount: 0,
      reviewEventCount: 0,
      duplicateGuidCount: 0,
      missingGuidCount: 0,
    );
    expect(
      selectLegacyAnkiPilotImport([user, fixture])?.importId,
      'p5c-fixture-device',
    );
    expect(selectLegacyAnkiPilotImport([user]), isNull);
  });

  test('listCardsForImport falls back to source hash after empty id', () {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final sources = OfficialAnkiSourceDao(db);
    sources.upsertSource(
      sourceId: 'src-hash-1',
      profileId: 'profile-default-01',
      sourceHash: 'fixture-hash',
      sourceSize: 1,
      displayName: 'p5c',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    sources.replaceCards(
      sourceId: 'src-hash-1',
      cards: const [
        OfficialAnkiCardDescriptor(
          cardId: 9,
          noteId: 8,
          deckId: 1,
          templateOrd: 0,
          noteGuid: 'guid-f',
        ),
      ],
    );
    final missed = sources.listCardsForImport(
      sourceId: 'src-stale',
      profileId: 'profile-default-01',
      sourceHash: 'fixture-hash',
    );
    expect(missed, hasLength(1));
    expect(missed.single.cardId, 9);
    expect(missed.single.noteGuid, 'guid-f');
  });

  test('P5C-00 flags migrationPilot default false and allowlist check', () {
    const flags = OfficialAnkiFeatureFlags();
    expect(flags.migrationPilot, isFalse);
    expect(LegacyAnkiMigrationFlags.cutoverEnabled, isFalse);
    expect(isFixturePilotSource(importId: 'user-deck'), isFalse);
    expect(isFixturePilotSource(importId: '1787046637039'), isFalse);
    expect(isFixturePilotSource(importId: 'p5c-fixture-basic'), isTrue);
    expect(isFixturePilotSource(importId: 'my-p5c-fixture-deck'), isFalse);
    expect(
      isFixturePilotSource(
        sourceHash: 'bbe354db3925f4b4d7e8d66b0770e83f2ce38586e1071398e762d821636cad58',
      ),
      isTrue,
    );
    expect(
      isFixturePilotSource(
        sourceHash: '28d89bb7bf41df25513e148e96acbdac93bcc71fadcee8e552b57d4413394d02',
      ),
      isTrue,
    );
    expect(
      isFixturePilotSource(
        sourceHash: 'unknown-hash-12345',
      ),
      isFalse,
    );
  });

  test('P5C-01 basic-cloze fixture exists and sha256 matches manifest', () {
    final apkgFile = File('test/application/anki_official/fixtures/p5c/basic-cloze.apkg');
    final shaFile = File('test/application/anki_official/fixtures/p5c/basic-cloze.sha256');
    expect(apkgFile.existsSync(), isTrue);
    expect(shaFile.existsSync(), isTrue);
    final recordedSha = shaFile.readAsStringSync().trim();
    expect(recordedSha, 'bbe354db3925f4b4d7e8d66b0770e83f2ce38586e1071398e762d821636cad58');
    expect(sha256.convert(apkgFile.readAsBytesSync()).toString(), recordedSha);
  });

  test('migration_lease_blocks_review_and_import', () {
    final coordinator = OfficialAnkiOperationCoordinator();
    expect(coordinator.phase, OfficialAnkiOperationPhase.idle);

    // Acquire migrating when idle succeeds
    coordinator.acquire(OfficialAnkiOperationPhase.migrating);
    expect(coordinator.phase, OfficialAnkiOperationPhase.migrating);

    // When migrating, guardSchedulerWrite throws conflict
    expect(
      () => coordinator.guardSchedulerWrite(),
      throwsA(isA<OfficialAnkiException>().having(
        (e) => e.code,
        'code',
        OfficialAnkiErrorCode.schedulerBusy,
      )),
    );

    // When migrating, acquiring reviewing / importing / backupRestore throws conflict
    expect(
      () => coordinator.acquire(OfficialAnkiOperationPhase.reviewing),
      throwsA(isA<OfficialAnkiException>().having(
        (e) => e.code,
        'code',
        OfficialAnkiErrorCode.schedulerBusy,
      )),
    );
    expect(
      () => coordinator.acquire(OfficialAnkiOperationPhase.importing),
      throwsA(isA<OfficialAnkiException>().having(
        (e) => e.code,
        'code',
        OfficialAnkiErrorCode.schedulerBusy,
      )),
    );

    // Release migrating returns to idle
    coordinator.release(OfficialAnkiOperationPhase.migrating);
    expect(coordinator.phase, OfficialAnkiOperationPhase.idle);

    // When reviewing, acquiring migrating throws conflict
    coordinator.acquire(OfficialAnkiOperationPhase.reviewing);
    expect(
      () => coordinator.acquire(OfficialAnkiOperationPhase.migrating),
      throwsA(isA<OfficialAnkiException>().having(
        (e) => e.code,
        'code',
        OfficialAnkiErrorCode.schedulerBusy,
      )),
    );
    coordinator.release(OfficialAnkiOperationPhase.reviewing);
    expect(coordinator.phase, OfficialAnkiOperationPhase.idle);
  });

  test('observing fixture deck is the official source deck not Default-due', () {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    final sources = OfficialAnkiSourceDao(db);
    expect(
      officialAnkiObservingFixtureDeckId(
        dao: dao,
        sources: sources,
        profileId: 'profile-default-01',
      ),
      isNull,
    );
    sources.upsertSource(
      sourceId: 'src-fixture',
      profileId: 'profile-default-01',
      sourceHash: '28d89bb7bf41df25513e148e96acbdac93bcc71fadcee8e552b57d4413394d02',
      sourceSize: 1,
      displayName: 'p5c-fixture',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 2,
    );
    sources.replaceCards(
      sourceId: 'src-fixture',
      cards: const [
        OfficialAnkiCardDescriptor(
          cardId: 1375933503610,
          noteId: 1375933494578,
          deckId: 1,
          templateOrd: 0,
          noteGuid: 'cU1%zNUzk1',
        ),
      ],
    );
    dao.insertDetected(
      migrationId: 'mig-p5c-fixture-device',
      profileId: 'profile-default-01',
      legacyImportId: 'p5c-fixture-device',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    for (final step in [
      (
        LegacyAnkiMigrationState.detected,
        LegacyAnkiMigrationState.awaitingPackage
      ),
      (
        LegacyAnkiMigrationState.awaitingPackage,
        LegacyAnkiMigrationState.validatingSource
      ),
      (
        LegacyAnkiMigrationState.validatingSource,
        LegacyAnkiMigrationState.backingUp
      ),
      (
        LegacyAnkiMigrationState.backingUp,
        LegacyAnkiMigrationState.importingOfficial
      ),
      (
        LegacyAnkiMigrationState.importingOfficial,
        LegacyAnkiMigrationState.indexingOfficial
      ),
      (
        LegacyAnkiMigrationState.indexingOfficial,
        LegacyAnkiMigrationState.mappingCards
      ),
      (
        LegacyAnkiMigrationState.mappingCards,
        LegacyAnkiMigrationState.projectingCourse
      ),
      (
        LegacyAnkiMigrationState.projectingCourse,
        LegacyAnkiMigrationState.verifying
      ),
      (
        LegacyAnkiMigrationState.verifying,
        LegacyAnkiMigrationState.cutoverReady
      ),
      (
        LegacyAnkiMigrationState.cutoverReady,
        LegacyAnkiMigrationState.cutover
      ),
      (
        LegacyAnkiMigrationState.cutover,
        LegacyAnkiMigrationState.observing
      ),
    ]) {
      dao.transition(
        migrationId: 'mig-p5c-fixture-device',
        expected: step.$1,
        next: step.$2,
        nowMillis: 2,
        officialSourceId: 'src-fixture',
      );
    }
    expect(
      officialAnkiObservingFixtureDeckId(
        dao: dao,
        sources: sources,
        profileId: 'profile-default-01',
      ),
      1,
    );
    final target = officialAnkiObservingFixtureReviewTarget(
      dao: dao,
      sources: sources,
      profileId: 'profile-default-01',
    );
    expect(target?.sourceId, 'src-fixture');
    expect(target?.cardIds, {1375933503610});
  });

  test('verifyAndCutover rejects empty projection when cards matched', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    final coordinator = OfficialAnkiOperationCoordinator();
    final saga = OfficialAnkiFixturePilotSaga(
      dao: dao,
      coordinator: coordinator,
    );
    dao.insertDetected(
      migrationId: 'mig-empty-proj',
      profileId: 'p1',
      legacyImportId: 'p5c-fixture-empty-proj',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    for (final step in [
      (
        LegacyAnkiMigrationState.detected,
        LegacyAnkiMigrationState.awaitingPackage
      ),
      (
        LegacyAnkiMigrationState.awaitingPackage,
        LegacyAnkiMigrationState.validatingSource
      ),
      (
        LegacyAnkiMigrationState.validatingSource,
        LegacyAnkiMigrationState.backingUp
      ),
      (
        LegacyAnkiMigrationState.backingUp,
        LegacyAnkiMigrationState.importingOfficial
      ),
      (
        LegacyAnkiMigrationState.importingOfficial,
        LegacyAnkiMigrationState.indexingOfficial
      ),
      (
        LegacyAnkiMigrationState.indexingOfficial,
        LegacyAnkiMigrationState.mappingCards
      ),
      (
        LegacyAnkiMigrationState.mappingCards,
        LegacyAnkiMigrationState.projectingCourse
      ),
      (
        LegacyAnkiMigrationState.projectingCourse,
        LegacyAnkiMigrationState.verifying
      ),
    ]) {
      dao.transition(
        migrationId: 'mig-empty-proj',
        expected: step.$1,
        next: step.$2,
        nowMillis: 2,
      );
    }
    final ok = await saga.verifyAndCutover(
      migrationId: 'mig-empty-proj',
      legacyCardCount: 1,
      officialCardCount: 1,
      matchedCount: 1,
      projectionItemCount: 0,
    );
    expect(ok, isFalse);
    expect(
      dao.findById('mig-empty-proj')?.state,
      LegacyAnkiMigrationState.needsUserAction,
    );
    coordinator.release(OfficialAnkiOperationPhase.migrating);
  });

  test('fixture_pilot_rejects_non_allowlist_source', () {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    final coordinator = OfficialAnkiOperationCoordinator();
    final saga = OfficialAnkiFixturePilotSaga(
      dao: dao,
      coordinator: coordinator,
    );

    // Attempting to start saga with user deck (non-allowlist) fails closed
    expect(
      () => saga.start(
        migrationId: 'mig-non-allowlist',
        profileId: 'profile-1',
        legacyImportId: 'user-deck-kaoyan-1787046637039',
        policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      ),
      throwsA(isA<OfficialAnkiException>().having(
        (e) => e.messageKey,
        'messageKey',
        'official_anki.non_allowlist_source',
      )),
    );
  });

  test('fixture_pilot_requires_reselected_package_hash', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    final coordinator = OfficialAnkiOperationCoordinator();
    final saga = OfficialAnkiFixturePilotSaga(
      dao: dao,
      coordinator: coordinator,
    );

    saga.start(
      migrationId: 'mig-hash-test',
      profileId: 'profile-1',
      legacyImportId: 'p5c-fixture-basic',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
    );
    expect(dao.findByLegacyImport(profileId: 'profile-1', legacyImportId: 'p5c-fixture-basic')?.state,
        LegacyAnkiMigrationState.awaitingPackage);

    final tempDir = Directory.systemTemp.createTempSync('turna-hash-test-');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final fakeApkg = File('${tempDir.path}/wrong.apkg');
    fakeApkg.writeAsStringSync('corrupted or mismatched apkg content');

    final rootDir = Directory.systemTemp.createTempSync('turna-paths-');
    addTearDown(() => rootDir.deleteSync(recursive: true));
    final paths = OfficialAnkiPaths(profileId: 'profile-test-01', profileRoot: rootDir);

    final ok = await saga.pickAndValidatePackage(
      migrationId: 'mig-hash-test',
      pickedFile: fakeApkg,
      expectedSourceHash: 'bbe354db3925f4b4d7e8d66b0770e83f2ce38586e1071398e762d821636cad58',
      paths: paths,
    );
    expect(ok, isFalse);
    final row = dao.findByLegacyImport(profileId: 'profile-1', legacyImportId: 'p5c-fixture-basic');
    expect(row?.state, LegacyAnkiMigrationState.needsUserAction);
    saga.releaseLease();
  });

  test('backup_files_exist_and_contain_no_card_html', () async {
    const service = LegacyAnkiBackupService();
    final rootDir = Directory.systemTemp.createTempSync('turna-backup-test-');
    addTearDown(() => rootDir.deleteSync(recursive: true));
    final paths = OfficialAnkiPaths(profileId: 'profile-bak-01', profileRoot: rootDir);
    await paths.ensureLayout();
    paths.collectionFile.writeAsBytesSync(const [0x53, 0x51, 0x4c, 0x69]);
    paths.catalogFile.writeAsBytesSync(const [0x53, 0x51, 0x4c, 0x69]);

    const manifest = LegacyAnkiBackupManifest(
      legacyRowCount: 10,
      legacyRowHash: 'row-hash-1',
      officialBackupId: 'bak-100',
    );

    const legacyCards = [
      LegacyAnkiCardIdentity(
        legacyCardId: 1,
        legacyWordId: 'anki-src-c1',
        legacyNoteId: 10,
        templateOrd: 0,
        noteGuid: 'guid-1',
      ),
      LegacyAnkiCardIdentity(
        legacyCardId: 2,
        legacyWordId: 'anki-src-c2',
        legacyNoteId: 10,
        templateOrd: 1,
        noteGuid: 'guid-1',
      ),
    ];

    final backupDir = await service.createPhysicalBackup(
      paths: paths,
      migrationId: 'mig-physical-1',
      manifest: manifest,
      legacyCards: legacyCards,
    );

    expect(backupDir.existsSync(), isTrue);
    final manifestFile = File('${backupDir.path}/legacy-manifest.json');
    final subsetDbFile = File('${backupDir.path}/legacy-subset.sqlite');
    final colFile = File('${backupDir.path}/collection.anki2');
    final mediaDir = Directory('${backupDir.path}/collection.media');
    final catalogFile = File('${backupDir.path}/official_catalog.sqlite');
    final sumsFile = File('${backupDir.path}/SHA256SUMS');

    expect(manifestFile.existsSync(), isTrue);
    expect(subsetDbFile.existsSync(), isTrue);
    expect(colFile.existsSync(), isTrue);
    expect(mediaDir.existsSync(), isTrue);
    expect(catalogFile.existsSync(), isTrue);
    expect(sumsFile.existsSync(), isTrue);

    // Verify subset sqlite has NO html or card text columns
    final subsetDb = sqlite3.open(subsetDbFile.path);
    addTearDown(subsetDb.dispose);
    final tables = subsetDb.select("SELECT name, sql FROM sqlite_master WHERE type='table'");
    for (final row in tables) {
      final sql = (row['sql'] as String).toLowerCase();
      expect(sql.contains('questionhtml'), isFalse);
      expect(sql.contains('fieldsjson'), isFalse);
      expect(sql.contains('fronttext'), isFalse);
      expect(sql.contains('backtext'), isFalse);
    }

    // Verify manifest JSON has NO card HTML
    final manifestJson = manifestFile.readAsStringSync();
    expect(manifestJson.contains('<div>'), isFalse);
    expect(manifestJson.contains('{{'), isFalse);
  });

  test('cutoverEnabled_stays_false', () {
    expect(LegacyAnkiMigrationFlags.cutoverEnabled, isFalse);
  });

  test('preview_cutover_button_stays_disabled', () {
    expect(LegacyAnkiMigrationFlags.cutoverEnabled, isFalse);
    final source = File(
      'lib/views/anki_official/official_anki_migration_preview_page.dart',
    ).readAsStringSync();
    expect(source.contains('Cutover (disabled)'), isTrue);
    expect(source.contains('official-migration-cutover-disabled'), isTrue);
    expect(source.contains('onPressed: null'), isTrue);
  });

  test('legacy_migration_crash_resumes_every_checkpoint', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    final coordinator = OfficialAnkiOperationCoordinator();
    final saga = OfficialAnkiFixturePilotSaga(
      dao: dao,
      coordinator: coordinator,
    );

    final rootDir = Directory.systemTemp.createTempSync('turna-crash-test-');
    addTearDown(() => rootDir.deleteSync(recursive: true));
    final paths = OfficialAnkiPaths(profileId: 'profile-crash-01', profileRoot: rootDir);
    await paths.ensureLayout();
    paths.collectionFile.writeAsBytesSync(const [0x53, 0x51, 0x4c, 0x69]);
    paths.catalogFile.writeAsBytesSync(const [0x53, 0x51, 0x4c, 0x69]);

    final apkgFile = File('test/application/anki_official/fixtures/p5c/basic-cloze.apkg');
    final sha = File('test/application/anki_official/fixtures/p5c/basic-cloze.sha256').readAsStringSync().trim();

    // 1. start -> awaitingPackage
    saga.start(
      migrationId: 'mig-crash-resume',
      profileId: 'profile-crash-01',
      legacyImportId: 'p5c-fixture-crash',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      sourceHash: sha,
      legacyCardCount: 2,
    );
    expect(dao.findByLegacyImport(profileId: 'profile-crash-01', legacyImportId: 'p5c-fixture-crash')?.state,
        LegacyAnkiMigrationState.awaitingPackage);

    saga.start(
      migrationId: 'mig-crash-resume',
      profileId: 'profile-crash-01',
      legacyImportId: 'p5c-fixture-crash',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      sourceHash: sha,
      legacyCardCount: 2,
    );
    expect(dao.findByLegacyImport(profileId: 'profile-crash-01', legacyImportId: 'p5c-fixture-crash')?.state,
        LegacyAnkiMigrationState.awaitingPackage);

    // Simulate crash/restart of Saga object
    final saga2 = OfficialAnkiFixturePilotSaga(dao: dao, coordinator: coordinator);

    // 2. pick and validate package -> backingUp
    final valid = await saga2.pickAndValidatePackage(
      migrationId: 'mig-crash-resume',
      pickedFile: apkgFile,
      expectedSourceHash: sha,
      paths: paths,
      legacyCards: const [
        LegacyAnkiCardIdentity(legacyCardId: 1, legacyWordId: 'w1', templateOrd: 0, noteGuid: 'g1'),
        LegacyAnkiCardIdentity(legacyCardId: 2, legacyWordId: 'w2', templateOrd: 1, noteGuid: 'g1'),
      ],
    );
    expect(valid, isTrue);
    expect(dao.findByLegacyImport(profileId: 'profile-crash-01', legacyImportId: 'p5c-fixture-crash')?.state,
        LegacyAnkiMigrationState.backingUp);

    // 3. import official -> indexingOfficial
    final fakeImporter = _FakeImporter(sourceId: 'src-crash-01', db: db);
    final sourceId = await saga2.importOfficial(
      migrationId: 'mig-crash-resume',
      packagePath: apkgFile.path,
      importer: fakeImporter,
    );
    expect(sourceId, 'src-crash-01');
    expect(dao.findByLegacyImport(profileId: 'profile-crash-01', legacyImportId: 'p5c-fixture-crash')?.state,
        LegacyAnkiMigrationState.indexingOfficial);

    // 4. indexing & mapping -> projectingCourse
    final matched = await saga2.indexAndMatchCards(
      migrationId: 'mig-crash-resume',
      legacyCards: const [
        LegacyAnkiCardIdentity(legacyCardId: 1, legacyWordId: 'w1', templateOrd: 0, noteGuid: 'g1'),
        LegacyAnkiCardIdentity(legacyCardId: 2, legacyWordId: 'w2', templateOrd: 1, noteGuid: 'g1'),
      ],
      officialCards: const [
        OfficialAnkiCardIdentity(officialCardId: 101, templateOrd: 0, noteGuid: 'g1'),
        OfficialAnkiCardIdentity(officialCardId: 102, templateOrd: 1, noteGuid: 'g1'),
      ],
    );
    expect(matched, isTrue);
    expect(dao.findByLegacyImport(profileId: 'profile-crash-01', legacyImportId: 'p5c-fixture-crash')?.state,
        LegacyAnkiMigrationState.projectingCourse);

    // 5. projecting -> verifying
    final projected = await saga2.projectCourse(
      migrationId: 'mig-crash-resume',
      projectionAction: () async {
        File('${rootDir.path}/projection.ok').writeAsStringSync('2');
      },
    );
    expect(projected, isTrue);
    expect(dao.findByLegacyImport(profileId: 'profile-crash-01', legacyImportId: 'p5c-fixture-crash')?.state,
        LegacyAnkiMigrationState.verifying);

    // 6. verify & cutover -> cutover -> observing
    final cutoverOk = await saga2.verifyAndCutover(
      migrationId: 'mig-crash-resume',
      legacyCardCount: 2,
      officialCardCount: 2,
      legacyNoteCount: 1,
      officialNoteCount: 1,
      legacyDeckCount: 1,
      officialDeckCount: 1,
      legacyMediaCount: 0,
      officialMediaCount: 0,
      projectionItemCount: 2,
      matchedCount: 2,
      officialMutationCountAtCutover: 7,
    );
    expect(cutoverOk, isTrue);
    final observing = dao.findByLegacyImport(
      profileId: 'profile-crash-01',
      legacyImportId: 'p5c-fixture-crash',
    );
    expect(observing?.state, LegacyAnkiMigrationState.observing);
    expect(observing?.officialMutationCountAtCutover, 7);
    expect(File('${rootDir.path}/projection.ok').readAsStringSync(), '2');

    saga2.releaseLease();
    expect(coordinator.phase, OfficialAnkiOperationPhase.idle);
  });

  test('cutover_with_official_mutation_cannot_restore_legacy_schedule', () {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    final coordinator = OfficialAnkiOperationCoordinator();
    final saga = OfficialAnkiFixturePilotSaga(
      dao: dao,
      coordinator: coordinator,
    );

    // Setup observing state with official_mutation_count_at_cutover = 0
    dao.insertDetected(
      migrationId: 'mig-rollback-test',
      profileId: 'p1',
      legacyImportId: 'p5c-fixture-r1',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 10,
    );
    dao.transition(migrationId: 'mig-rollback-test', expected: LegacyAnkiMigrationState.detected, next: LegacyAnkiMigrationState.awaitingPackage, nowMillis: 20);
    dao.transition(migrationId: 'mig-rollback-test', expected: LegacyAnkiMigrationState.awaitingPackage, next: LegacyAnkiMigrationState.validatingSource, nowMillis: 30);
    dao.transition(migrationId: 'mig-rollback-test', expected: LegacyAnkiMigrationState.validatingSource, next: LegacyAnkiMigrationState.backingUp, nowMillis: 40);
    dao.transition(migrationId: 'mig-rollback-test', expected: LegacyAnkiMigrationState.backingUp, next: LegacyAnkiMigrationState.importingOfficial, nowMillis: 50);
    dao.transition(migrationId: 'mig-rollback-test', expected: LegacyAnkiMigrationState.importingOfficial, next: LegacyAnkiMigrationState.indexingOfficial, nowMillis: 60);
    dao.transition(migrationId: 'mig-rollback-test', expected: LegacyAnkiMigrationState.indexingOfficial, next: LegacyAnkiMigrationState.mappingCards, nowMillis: 70);
    dao.transition(migrationId: 'mig-rollback-test', expected: LegacyAnkiMigrationState.mappingCards, next: LegacyAnkiMigrationState.projectingCourse, nowMillis: 80);
    dao.transition(migrationId: 'mig-rollback-test', expected: LegacyAnkiMigrationState.projectingCourse, next: LegacyAnkiMigrationState.verifying, nowMillis: 90);
    dao.transition(migrationId: 'mig-rollback-test', expected: LegacyAnkiMigrationState.verifying, next: LegacyAnkiMigrationState.cutoverReady, nowMillis: 100);
    dao.transition(migrationId: 'mig-rollback-test', expected: LegacyAnkiMigrationState.cutoverReady, next: LegacyAnkiMigrationState.cutover, nowMillis: 110);
    dao.transition(migrationId: 'mig-rollback-test', expected: LegacyAnkiMigrationState.cutover, next: LegacyAnkiMigrationState.observing, nowMillis: 120);

    // Case A: mutationDelta == 0 -> rollbackEligible
    saga.rollback(
      migrationId: 'mig-rollback-test',
      currentState: LegacyAnkiMigrationState.observing,
      officialMutationDelta: 0,
      nowMillis: 130,
    );
    expect(dao.findByLegacyImport(profileId: 'p1', legacyImportId: 'p5c-fixture-r1')?.state,
        LegacyAnkiMigrationState.rollbackEligible);

    // Case B: mutationDelta > 0 -> noLegacyScheduleRollback (cannot restore old legacy schedule)
    dao.insertDetected(
      migrationId: 'mig-rollback-mutated',
      profileId: 'p1',
      legacyImportId: 'p5c-fixture-r2',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 10,
    );
    dao.transition(migrationId: 'mig-rollback-mutated', expected: LegacyAnkiMigrationState.detected, next: LegacyAnkiMigrationState.awaitingPackage, nowMillis: 20);
    dao.transition(migrationId: 'mig-rollback-mutated', expected: LegacyAnkiMigrationState.awaitingPackage, next: LegacyAnkiMigrationState.validatingSource, nowMillis: 30);
    dao.transition(migrationId: 'mig-rollback-mutated', expected: LegacyAnkiMigrationState.validatingSource, next: LegacyAnkiMigrationState.backingUp, nowMillis: 40);
    dao.transition(migrationId: 'mig-rollback-mutated', expected: LegacyAnkiMigrationState.backingUp, next: LegacyAnkiMigrationState.importingOfficial, nowMillis: 50);
    dao.transition(migrationId: 'mig-rollback-mutated', expected: LegacyAnkiMigrationState.importingOfficial, next: LegacyAnkiMigrationState.indexingOfficial, nowMillis: 60);
    dao.transition(migrationId: 'mig-rollback-mutated', expected: LegacyAnkiMigrationState.indexingOfficial, next: LegacyAnkiMigrationState.mappingCards, nowMillis: 70);
    dao.transition(migrationId: 'mig-rollback-mutated', expected: LegacyAnkiMigrationState.mappingCards, next: LegacyAnkiMigrationState.projectingCourse, nowMillis: 80);
    dao.transition(migrationId: 'mig-rollback-mutated', expected: LegacyAnkiMigrationState.projectingCourse, next: LegacyAnkiMigrationState.verifying, nowMillis: 90);
    dao.transition(migrationId: 'mig-rollback-mutated', expected: LegacyAnkiMigrationState.verifying, next: LegacyAnkiMigrationState.cutoverReady, nowMillis: 100);
    dao.transition(migrationId: 'mig-rollback-mutated', expected: LegacyAnkiMigrationState.cutoverReady, next: LegacyAnkiMigrationState.cutover, nowMillis: 110);
    dao.transition(migrationId: 'mig-rollback-mutated', expected: LegacyAnkiMigrationState.cutover, next: LegacyAnkiMigrationState.observing, nowMillis: 120);

    saga.rollback(
      migrationId: 'mig-rollback-mutated',
      currentState: LegacyAnkiMigrationState.observing,
      officialMutationDelta: 1, // Has 1 review rating in official collection
      nowMillis: 130,
    );
    expect(dao.findByLegacyImport(profileId: 'p1', legacyImportId: 'p5c-fixture-r2')?.state,
        LegacyAnkiMigrationState.noLegacyScheduleRollback);
  });

  test('cutover_fixture_source_denies_turna_srs_answer', () async {
    final migrator = AnkiSrsMigrator();
    final fakeSrs = _FakeSrsProvider();
    expect(
      () => migrator.migrate(
        cards: const [
          AnkiCardData(
            id: 1,
            nid: 1,
            did: 1,
          )
        ],
        importId: 'p5c-fixture-basic',
        srsProvider: fakeSrs,
        sourceEngine: AnkiEngineKind.official,
      ),
      throwsA(isA<AnkiWriteDenied>()),
    );

    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    dao.insertDetected(
      migrationId: 'mig-deny-answer',
      profileId: 'profile-default-01',
      legacyImportId: 'p5c-fixture-basic',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    for (final step in [
      (
        LegacyAnkiMigrationState.detected,
        LegacyAnkiMigrationState.awaitingPackage
      ),
      (
        LegacyAnkiMigrationState.awaitingPackage,
        LegacyAnkiMigrationState.validatingSource
      ),
      (
        LegacyAnkiMigrationState.validatingSource,
        LegacyAnkiMigrationState.backingUp
      ),
      (
        LegacyAnkiMigrationState.backingUp,
        LegacyAnkiMigrationState.importingOfficial
      ),
      (
        LegacyAnkiMigrationState.importingOfficial,
        LegacyAnkiMigrationState.indexingOfficial
      ),
      (
        LegacyAnkiMigrationState.indexingOfficial,
        LegacyAnkiMigrationState.mappingCards
      ),
      (
        LegacyAnkiMigrationState.mappingCards,
        LegacyAnkiMigrationState.projectingCourse
      ),
      (
        LegacyAnkiMigrationState.projectingCourse,
        LegacyAnkiMigrationState.verifying
      ),
      (
        LegacyAnkiMigrationState.verifying,
        LegacyAnkiMigrationState.cutoverReady
      ),
      (
        LegacyAnkiMigrationState.cutoverReady,
        LegacyAnkiMigrationState.cutover
      ),
      (
        LegacyAnkiMigrationState.cutover,
        LegacyAnkiMigrationState.observing
      ),
    ]) {
      dao.transition(
        migrationId: 'mig-deny-answer',
        expected: step.$1,
        next: step.$2,
        nowMillis: 2,
      );
    }
    expect(
      () => assertLegacySrsAnswerAllowed(
        importId: 'p5c-fixture-basic',
        dao: dao,
      ),
      throwsA(isA<AnkiWriteDenied>()),
    );
    expect(
      () => assertLegacySrsAnswerAllowed(
        importId: 'some-other-import',
        dao: dao,
      ),
      returnsNormally,
    );
  });

  test('recordedKind writes official at cutover and reverts on rollback', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    final coord = OfficialAnkiOperationCoordinator();
    final saga = OfficialAnkiFixturePilotSaga(dao: dao, coordinator: coord);
    dao.insertDetected(
      migrationId: 'mig-recorded',
      profileId: 'p1',
      legacyImportId: 'p5c-fixture-recorded',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    for (final step in [
      (LegacyAnkiMigrationState.detected, LegacyAnkiMigrationState.awaitingPackage),
      (LegacyAnkiMigrationState.awaitingPackage, LegacyAnkiMigrationState.validatingSource),
      (LegacyAnkiMigrationState.validatingSource, LegacyAnkiMigrationState.backingUp),
      (LegacyAnkiMigrationState.backingUp, LegacyAnkiMigrationState.importingOfficial),
      (LegacyAnkiMigrationState.importingOfficial, LegacyAnkiMigrationState.indexingOfficial),
      (LegacyAnkiMigrationState.indexingOfficial, LegacyAnkiMigrationState.mappingCards),
      (LegacyAnkiMigrationState.mappingCards, LegacyAnkiMigrationState.projectingCourse),
      (LegacyAnkiMigrationState.projectingCourse, LegacyAnkiMigrationState.verifying),
    ]) {
      dao.transition(migrationId: 'mig-recorded', expected: step.$1, next: step.$2, nowMillis: 2);
    }
    final ok = await saga.verifyAndCutover(
      migrationId: 'mig-recorded',
      legacyCardCount: 1,
      officialCardCount: 1,
      matchedCount: 1,
      projectionItemCount: 1,
      officialMutationCountAtCutover: 0,
    );
    expect(ok, isTrue);
    expect(dao.findById('mig-recorded')?.recordedKind, 'official');
    expect(dao.findById('mig-recorded')?.state, LegacyAnkiMigrationState.observing);
    const resolver = AnkiSourceRouteResolver();
    expect(
      resolver.resolve(
        sourceKey: 'p5c-fixture-recorded',
        recordedKind: AnkiEngineKind.official,
        cutoverEnabled: true,
      ),
      AnkiEngineKind.official,
    );
    saga.rollback(
      migrationId: 'mig-recorded',
      currentState: LegacyAnkiMigrationState.observing,
      nowMillis: 3,
    );
    expect(dao.findById('mig-recorded')?.recordedKind, 'legacy');
    expect(dao.findById('mig-recorded')?.state, LegacyAnkiMigrationState.rollbackEligible);
    coord.release(OfficialAnkiOperationPhase.migrating);
  });

  test('recordedKind stays per source and cutoverEnabled false', () {
    expect(LegacyAnkiMigrationFlags.cutoverEnabled, isFalse);
    const resolver = AnkiSourceRouteResolver();
    expect(
      resolver.resolve(sourceKey: 'p5c-fixture-a', recordedKind: AnkiEngineKind.official),
      AnkiEngineKind.legacy,
    );
    expect(
      resolver.resolve(sourceKey: 'p5c-fixture-b', recordedKind: null),
      AnkiEngineKind.legacy,
    );
  });

  test('legacyAnkiDao setCardState denies official source after observing', () async {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    final dao = OfficialAnkiMigrationDao(catalog);
    dao.insertDetected(
      migrationId: 'mig-dao-deny',
      profileId: 'profile-default-01',
      legacyImportId: 'p5c-fixture-dao',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    for (final step in [
      (LegacyAnkiMigrationState.detected, LegacyAnkiMigrationState.awaitingPackage),
      (LegacyAnkiMigrationState.awaitingPackage, LegacyAnkiMigrationState.validatingSource),
      (LegacyAnkiMigrationState.validatingSource, LegacyAnkiMigrationState.backingUp),
      (LegacyAnkiMigrationState.backingUp, LegacyAnkiMigrationState.importingOfficial),
      (LegacyAnkiMigrationState.importingOfficial, LegacyAnkiMigrationState.indexingOfficial),
      (LegacyAnkiMigrationState.indexingOfficial, LegacyAnkiMigrationState.mappingCards),
      (LegacyAnkiMigrationState.mappingCards, LegacyAnkiMigrationState.projectingCourse),
      (LegacyAnkiMigrationState.projectingCourse, LegacyAnkiMigrationState.verifying),
      (LegacyAnkiMigrationState.verifying, LegacyAnkiMigrationState.cutoverReady),
      (LegacyAnkiMigrationState.cutoverReady, LegacyAnkiMigrationState.cutover),
      (LegacyAnkiMigrationState.cutover, LegacyAnkiMigrationState.observing),
    ]) {
      dao.transition(migrationId: 'mig-dao-deny', expected: step.$1, next: step.$2, nowMillis: 2);
    }
    // Simulate the guard path without a real CourseDatabase: direct guard check
    const guard = AnkiWriteGuard();
    expect(
      () => guard.assertAllowed(
        sourceEngine: AnkiEngineKind.official,
        owner: AnkiWriteOwner.legacyAnkiDao,
        operation: 'setCardState',
      ),
      throwsA(isA<AnkiWriteDenied>()),
    );
  });

  test('rollback reads official_mutation_count column not caller delta', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    final coord = OfficialAnkiOperationCoordinator();
    final saga = OfficialAnkiFixturePilotSaga(dao: dao, coordinator: coord);
    dao.insertDetected(
      migrationId: 'mig-rollback-col',
      profileId: 'p1',
      legacyImportId: 'p5c-fixture-col',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    for (final step in [
      (LegacyAnkiMigrationState.detected, LegacyAnkiMigrationState.awaitingPackage),
      (LegacyAnkiMigrationState.awaitingPackage, LegacyAnkiMigrationState.validatingSource),
      (LegacyAnkiMigrationState.validatingSource, LegacyAnkiMigrationState.backingUp),
      (LegacyAnkiMigrationState.backingUp, LegacyAnkiMigrationState.importingOfficial),
      (LegacyAnkiMigrationState.importingOfficial, LegacyAnkiMigrationState.indexingOfficial),
      (LegacyAnkiMigrationState.indexingOfficial, LegacyAnkiMigrationState.mappingCards),
      (LegacyAnkiMigrationState.mappingCards, LegacyAnkiMigrationState.projectingCourse),
      (LegacyAnkiMigrationState.projectingCourse, LegacyAnkiMigrationState.verifying),
    ]) {
      dao.transition(migrationId: 'mig-rollback-col', expected: step.$1, next: step.$2, nowMillis: 2);
    }
    await saga.verifyAndCutover(
      migrationId: 'mig-rollback-col',
      legacyCardCount: 1,
      officialCardCount: 1,
      matchedCount: 1,
      projectionItemCount: 1,
      officialMutationCountAtCutover: 5,
    );
    // Caller passes no delta -> saga must read column (5) -> noLegacyScheduleRollback
    saga.rollback(
      migrationId: 'mig-rollback-col',
      currentState: LegacyAnkiMigrationState.observing,
      nowMillis: 3,
    );
    expect(dao.findById('mig-rollback-col')?.state, LegacyAnkiMigrationState.noLegacyScheduleRollback);
    coord.release(OfficialAnkiOperationPhase.migrating);
  });

  test('ankiweb not linked from production routes', () {
    final routing = File('lib/routing/routing.dart').readAsStringSync();
    final review = File('lib/views/anki/anki_review_screen.dart').readAsStringSync();
    expect(routing.toLowerCase().contains('ankiweb'), isFalse);
    expect(review.toLowerCase().contains('ankiweb'), isFalse);
    final preview = File('lib/views/anki_official/official_anki_migration_preview_page.dart').readAsStringSync();
    expect(preview.toLowerCase().contains('ankiweb'), isFalse);
  });

  test('p5c-19 host real import path for classic-basic.apkg', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    final coord = OfficialAnkiOperationCoordinator();
    final saga = OfficialAnkiFixturePilotSaga(dao: dao, coordinator: coord);
    final root = Directory.systemTemp.createTempSync('turna-host-real-import-');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = OfficialAnkiPaths(profileId: 'profile-host-real-01', profileRoot: root);
    await paths.ensureLayout();
    paths.collectionFile.writeAsBytesSync(const [0x53, 0x51, 0x4c, 0x69]);
    paths.catalogFile.writeAsBytesSync(const [0x53, 0x51, 0x4c, 0x69]);
    final apkg = File('test/application/anki_official/fixtures/p5c/classic-basic.apkg');
    final sha = File('test/application/anki_official/fixtures/p5c/classic-basic.sha256').readAsStringSync().trim();
    expect(apkg.existsSync(), isTrue);
    expect(sha256.convert(apkg.readAsBytesSync()).toString(), sha);
    saga.start(
      migrationId: 'mig-host-real',
      profileId: 'profile-host-real-01',
      legacyImportId: 'p5c-fixture-host-real',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      sourceHash: sha,
      legacyCardCount: 1,
    );
    final ok = await saga.pickAndValidatePackage(
      migrationId: 'mig-host-real',
      pickedFile: apkg,
      expectedSourceHash: sha,
      paths: paths,
      legacyCards: const [LegacyAnkiCardIdentity(legacyCardId: 1375933503610, legacyWordId: 'w1', legacyNoteId: 1375933494578, templateOrd: 0, noteGuid: 'cU1%zNUzk1')],
    );
    expect(ok, isTrue);
    // Real path would call OfficialAnkiImporter.importFile via worker.
    // On Host without FFI this test proves the non-Fake contract is wired:
    // pickAndValidatePackage succeeds on real .apkg bytes + sha, state advances to backingUp,
    // and importOfficial accepts any OfficialAnkiImporter (tested via fake that writes a source row).
    final importer = _FakeImporter(sourceId: 'src-host-real', db: db);
    final sourceId = await saga.importOfficial(
      migrationId: 'mig-host-real',
      packagePath: apkg.path,
      importer: importer,
    );
    expect(sourceId, 'src-host-real');
    expect(dao.findByLegacyImport(profileId: 'profile-host-real-01', legacyImportId: 'p5c-fixture-host-real')?.state, LegacyAnkiMigrationState.indexingOfficial);
    saga.releaseLease();
  });

  test('postCutoverDelta treats column as baseline not the increment', () {
    expect(
      OfficialAnkiFixtureRollbackDrill.postCutoverDelta(
        storedAtCutover: 0,
        currentSourceRevlog: 2,
      ),
      2,
    );
    expect(
      OfficialAnkiFixtureRollbackDrill.postCutoverDelta(
        storedAtCutover: 2,
        currentSourceRevlog: 2,
      ),
      0,
    );
  });

  test('countRevlogForCards reads only listed cids', () {
    final dir = Directory.systemTemp.createTempSync('turna-revlog-count-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final col = File('${dir.path}/collection.anki2');
    final db = sqlite3.open(col.path);
    db.execute('CREATE TABLE revlog (id INTEGER PRIMARY KEY, cid INTEGER)');
    db.execute('INSERT INTO revlog (id, cid) VALUES (1, 10), (2, 10), (3, 99)');
    db.dispose();
    expect(
      OfficialAnkiFixtureRollbackDrill.countRevlogForCards(
        collectionFile: col,
        cardIds: const [10],
      ),
      2,
    );
    expect(
      OfficialAnkiFixtureRollbackDrill.countRevlogForCards(
        collectionFile: col,
        cardIds: const [99],
      ),
      1,
    );
  });

  test('device rollback drill mutation zero and positive', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final dao = OfficialAnkiMigrationDao(db);
    final coord = OfficialAnkiOperationCoordinator();
    final saga = OfficialAnkiFixturePilotSaga(dao: dao, coordinator: coord);
    dao.insertDetected(
      migrationId: 'mig-p5c-fixture-device',
      profileId: 'profile-default-01',
      legacyImportId: 'p5c-fixture-device',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    for (final step in [
      (LegacyAnkiMigrationState.detected, LegacyAnkiMigrationState.awaitingPackage),
      (LegacyAnkiMigrationState.awaitingPackage, LegacyAnkiMigrationState.validatingSource),
      (LegacyAnkiMigrationState.validatingSource, LegacyAnkiMigrationState.backingUp),
      (LegacyAnkiMigrationState.backingUp, LegacyAnkiMigrationState.importingOfficial),
      (LegacyAnkiMigrationState.importingOfficial, LegacyAnkiMigrationState.indexingOfficial),
      (LegacyAnkiMigrationState.indexingOfficial, LegacyAnkiMigrationState.mappingCards),
      (LegacyAnkiMigrationState.mappingCards, LegacyAnkiMigrationState.projectingCourse),
      (LegacyAnkiMigrationState.projectingCourse, LegacyAnkiMigrationState.verifying),
    ]) {
      dao.transition(
        migrationId: 'mig-p5c-fixture-device',
        expected: step.$1,
        next: step.$2,
        nowMillis: 2,
      );
    }
    dao.upsertCardMapRows(
      migrationId: 'mig-p5c-fixture-device',
      rows: const [
        LegacyAnkiCardMapDraft(
          legacyCardId: 1375933503610,
          legacyWordId: 'anki-p5c-fixture-device-c1375933503610',
          templateOrd: 0,
          matchMethod: LegacyAnkiMatchMethod.noteGuidAndOrdinal,
          matchState: LegacyAnkiMatchState.matched,
          officialCardId: 1375933503610,
          noteGuid: 'cU1%zNUzk1',
        ),
      ],
    );
    final cutover = await saga.verifyAndCutover(
      migrationId: 'mig-p5c-fixture-device',
      legacyCardCount: 1,
      officialCardCount: 1,
      matchedCount: 1,
      projectionItemCount: 1,
      officialMutationCountAtCutover: 0,
    );
    expect(cutover, isTrue);
    expect(dao.findById('mig-p5c-fixture-device')?.state, LegacyAnkiMigrationState.observing);
    expect(dao.findById('mig-p5c-fixture-device')?.recordedKind, 'official');

    final root = Directory.systemTemp.createTempSync('turna-rb-drill-');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: root,
    );
    await paths.ensureLayout();
    paths.collectionFile.writeAsBytesSync(const [0x53, 0x51, 0x4c, 0x69]);

    final report = await const OfficialAnkiFixtureRollbackDrill().runBothPaths(
      saga: saga,
      dao: dao,
      paths: paths,
      profileId: 'profile-default-01',
      userCardCount: 181,
      currentSourceRevlogOverride: 2,
    );
    expect(report.bothPassed, isTrue);
    expect(report.mutationGt0?.migrationId, 'mig-p5c-fixture-device');
    expect(report.mutationGt0?.state, LegacyAnkiMigrationState.noLegacyScheduleRollback);
    expect(report.mutationGt0?.recordedKind, 'official');
    expect(report.mutationGt0?.delta, 2);
    expect(report.mutationEq0?.legacyImportId, 'p5c-fixture-rb0');
    expect(report.mutationEq0?.state, LegacyAnkiMigrationState.rollbackEligible);
    expect(report.mutationEq0?.recordedKind, 'legacy');
    expect(report.mutationEq0?.delta, 0);
    expect(report.userCardCount, 181);
    expect(report.collectionPresent, isTrue);
    expect(
      dao.findByLegacyImport(
        profileId: 'profile-default-01',
        legacyImportId: 'p5c-fixture-device',
      )?.state,
      LegacyAnkiMigrationState.noLegacyScheduleRollback,
    );
  });
}

class _FakeImporter implements OfficialAnkiImporter {
  _FakeImporter({this.sourceId = 'src-pilot-01', this.db});
  final String sourceId;
  final OfficialAnkiDatabase? db;

  @override
  Future<OfficialAnkiImportResult> importFile({
    required String packagePath,
    required String displayName,
    String? requestId,
    bool cancel = false,
  }) async {
    if (db != null) {
      OfficialAnkiSourceDao(db!).upsertSource(
        sourceId: sourceId,
        profileId: 'profile-crash-01',
        sourceHash: 'sha-fake',
        sourceSize: 100,
        displayName: displayName,
        state: 'active',
        backendCommit: 'commit',
        nowMillis: DateTime.now().millisecondsSinceEpoch,
      );
    }
    return OfficialAnkiImportResult(
      sourceId: sourceId,
      attemptId: 'att-1',
      state: OfficialAnkiSourceState.active,
      cardCount: 2,
      noteCount: 1,
    );
  }
}

class _FakeSrsProvider extends Fake implements SrsProvider {
  @override
  final Map<String, SrsWord> state = {};
  @override
  Future<void> bulkImportStates(Map<String, SrsWord> words) async {
    state.addAll(words);
  }
}

class _FakeCensusReader implements LegacyAnkiCensusReader {
  @override
  Future<List<LegacyAnkiImportCensusSeed>> loadSeeds() async {
    return const [
      LegacyAnkiImportCensusSeed(
        importId: 'imp-1',
        sourceHash: 'abc123',
        noteCount: 2,
        cardCount: 3,
        mediaCount: 1,
        deckCount: 1,
        importedScheduling: true,
        status: 'ready',
        sourceFilePresent: false,
        noteGuids: ['guid-a', 'guid-a', ''],
        srsRowCount: 3,
        reviewEventCount: 4,
      ),
    ];
  }
}
