import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/anki_srs_migrator.dart';
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
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
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
      AnkiEngineKind.official,
    );
    expect(
      resolver.resolve(
        sourceKey: 'src-official',
        officialCatalogHasSource: true,
        recordedKind: AnkiEngineKind.legacy,
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
      7,
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

  test('P5C-00 flags migrationPilot default false and allowlist check', () {
    const flags = OfficialAnkiFeatureFlags();
    expect(flags.migrationPilot, isFalse);
    expect(LegacyAnkiMigrationFlags.cutoverEnabled, isFalse);
    expect(isFixturePilotSource(importId: 'user-deck'), isFalse);
    expect(isFixturePilotSource(importId: '1787046637039'), isFalse);
    expect(isFixturePilotSource(importId: 'p5c-fixture-basic'), isTrue);
    expect(isFixturePilotSource(displayName: 'my-p5c-fixture-deck'), isTrue);
    expect(
      isFixturePilotSource(
        sourceHash: 'bbe354db3925f4b4d7e8d66b0770e83f2ce38586e1071398e762d821636cad58',
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
    const source = '''
      FilledButton(
        key: const Key('official-migration-cutover-disabled'),
        onPressed: LegacyAnkiMigrationFlags.cutoverEnabled ? () {} : null,
        child: const Text('Cutover (disabled)'),
      ),
    ''';
    expect(source.contains('Cutover (disabled)'), isTrue);
    expect(source.contains('official-migration-cutover-disabled'), isTrue);
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
      projectionAction: () async {},
    );
    expect(projected, isTrue);
    expect(dao.findByLegacyImport(profileId: 'profile-crash-01', legacyImportId: 'p5c-fixture-crash')?.state,
        LegacyAnkiMigrationState.verifying);

    // 6. verify & cutover -> cutover -> observing
    final cutoverOk = await saga2.verifyAndCutover(
      migrationId: 'mig-crash-resume',
      legacyCardCount: 2,
      officialCardCount: 2,
      officialMutationCountAtCutover: 0,
    );
    expect(cutoverOk, isTrue);
    expect(dao.findByLegacyImport(profileId: 'profile-crash-01', legacyImportId: 'p5c-fixture-crash')?.state,
        LegacyAnkiMigrationState.observing);

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
