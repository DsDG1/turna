import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_backup_manifest.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_legacy_source_migration_saga.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

class _NoopBackupService extends LegacyAnkiBackupService {
  const _NoopBackupService();

  @override
  Future<Directory> createPhysicalBackup({
    required OfficialAnkiPaths paths,
    required String migrationId,
    required LegacyAnkiBackupManifest manifest,
    List<LegacyAnkiCardIdentity>? legacyCards,
  }) async {
    final dir = Directory('${paths.backups.path}/w8/$migrationId');
    dir.createSync(recursive: true);
    return dir;
  }
}

class _FakeImporter implements OfficialAnkiImporter {
  _FakeImporter({
    required this.sources,
    this.sourceId = 'src-w8-01',
    this.profileId = 'profile-w8-test01',
  });

  final OfficialAnkiSourceDao sources;
  final String sourceId;
  final String profileId;
  int calls = 0;

  @override
  Future<OfficialAnkiImportResult> importFile({
    required String packagePath,
    required String displayName,
    String? requestId,
    bool cancel = false,
  }) async {
    calls += 1;
    sources.upsertSource(
      sourceId: sourceId,
      profileId: profileId,
      sourceHash: 'hash-$sourceId',
      sourceSize: 1,
      displayName: displayName,
      state: 'active',
      backendCommit: 'test',
      nowMillis: 1,
    );
    return OfficialAnkiImportResult(
      sourceId: sourceId,
      attemptId: 'att-$sourceId',
      state: OfficialAnkiSourceState.active,
      cardCount: 1,
      noteCount: 1,
    );
  }
}

void _ensureSource(
  OfficialAnkiDatabase db, {
  required String sourceId,
  String profileId = 'profile-w8-test01',
}) {
  OfficialAnkiSourceDao(db).upsertSource(
    sourceId: sourceId,
    profileId: profileId,
    sourceHash: 'hash-$sourceId',
    sourceSize: 1,
    displayName: sourceId,
    state: 'active',
    backendCommit: 'test',
    nowMillis: 1,
  );
}

void main() {
  late Directory tmp;
  late OfficialAnkiDatabase db;
  late OfficialAnkiMigrationDao dao;
  late OfficialAnkiOperationCoordinator coordinator;
  late OfficialLegacySourceMigrationSaga saga;
  late OfficialAnkiPaths paths;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('w8-legacy-mig-');
    db = OfficialAnkiDatabase.memory();
    dao = OfficialAnkiMigrationDao(db);
    coordinator = OfficialAnkiOperationCoordinator();
    saga = OfficialLegacySourceMigrationSaga(
      dao: dao,
      coordinator: coordinator,
      backupService: const _NoopBackupService(),
    );
    paths = OfficialAnkiPaths(
      profileId: 'profile-w8-test01',
      profileRoot: Directory('${tmp.path}/profile'),
    );
    await paths.ensureLayout();
  });

  tearDown(() async {
    db.close();
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  group('scheduling policy UX', () {
    test('all three policies expose user-visible labels; never silent reset', () {
      expect(
        LegacyAnkiSchedulingPolicy.preservePackageScheduling.userVisibleLabel,
        isNotEmpty,
      );
      expect(
        LegacyAnkiSchedulingPolicy.resetAsNew.userVisibleDescription,
        contains('New'),
      );
      expect(
        LegacyAnkiSchedulingPolicy.keepLegacyReadOnly.abandonsOfficialCutover,
        isTrue,
      );
      expect(
        legacyAnkiLosslessScheduleMapAvailable(
          nativeMigrationApiAvailable: false,
          turnaOnlyReviewsPresent: true,
        ),
        isFalse,
      );
    });

    test('begin refuses silent policy when lossless map is impossible', () {
      expect(
        () => saga.beginFromCleanLegacyCensus(
          migrationId: 'mig-1',
          profileId: 'profile-w8-test01',
          legacyImportId: 'legacy-imp-1',
          sourceHash: 'abc',
          policy: LegacyAnkiSchedulingPolicy.resetAsNew,
          policyConfirmedByUser: false,
          losslessScheduleMapAvailable: false,
          nowMillis: 1,
        ),
        throwsA(
          isA<OfficialAnkiException>().having(
            (e) => e.messageKey,
            'messageKey',
            'official_anki.scheduling_policy_requires_user_choice',
          ),
        ),
      );
    });
  });

  group('§12.4 journal resume', () {
    test('full happy path reaches cleanup-after-release completed', () async {
      final pkg = File('${tmp.path}/deck.apkg')..writeAsBytesSync([1, 2, 3]);
      final computed = sha256.convert(await pkg.readAsBytes()).toString();

      saga.beginFromCleanLegacyCensus(
        migrationId: 'mig-happy',
        profileId: 'profile-w8-test01',
        legacyImportId: 'legacy-happy',
        sourceHash: computed,
        policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
        policyConfirmedByUser: true,
        losslessScheduleMapAvailable: false,
        legacyCardCount: 1,
        nowMillis: 10,
      );
      expect(
        saga.resume(migrationId: 'mig-happy'),
        OfficialLegacyMigrationResumeAction.snapshotBackup,
      );

      final backed = await saga.snapshotAndBackup(
        migrationId: 'mig-happy',
        pickedFile: pkg,
        expectedSourceHash: computed,
        paths: paths,
        legacyCards: const [
          LegacyAnkiCardIdentity(
            legacyCardId: 1,
            legacyWordId: 'anki-legacy-happy-1',
            templateOrd: 0,
            legacyNoteId: 10,
            noteGuid: 'guid-1',
          ),
        ],
        nowMillis: 20,
      );
      expect(backed, isTrue);
      expect(
        saga.resume(migrationId: 'mig-happy'),
        OfficialLegacyMigrationResumeAction.importOrReconstruct,
      );

      final importer = _FakeImporter(sources: OfficialAnkiSourceDao(db));
      final sourceId = await saga.importOrReconstruct(
        migrationId: 'mig-happy',
        packagePath: pkg.path,
        importer: importer,
        nowMillis: 30,
      );
      expect(sourceId, 'src-w8-01');
      expect(importer.calls, 1);

      await saga.chooseSchedulingPolicy(
        migrationId: 'mig-happy',
        policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
        policyConfirmedByUser: true,
        losslessScheduleMapAvailable: false,
        nowMillis: 40,
      );

      final mapped = await saga.mapCardsAndProject(
        migrationId: 'mig-happy',
        legacyCards: const [
          LegacyAnkiCardIdentity(
            legacyCardId: 1,
            legacyWordId: 'anki-legacy-happy-1',
            templateOrd: 0,
            legacyNoteId: 10,
            noteGuid: 'guid-1',
          ),
        ],
        officialCards: const [
          OfficialAnkiCardIdentity(
            officialCardId: 1001,
            templateOrd: 0,
            officialNoteId: 10,
            noteGuid: 'guid-1',
          ),
        ],
        sameTrustedPackage: true,
        projectionAction: () async {},
        nowMillis: 50,
      );
      expect(mapped, isTrue);
      expect(
        saga.resume(migrationId: 'mig-happy'),
        OfficialLegacyMigrationResumeAction.compare,
      );

      final compared = await saga.compareCardinality(
        migrationId: 'mig-happy',
        legacyCardCount: 1,
        officialCardCount: 1,
        matchedCount: 1,
        projectionItemCount: 1,
        legacyNoteCount: 1,
        officialNoteCount: 1,
        nowMillis: 60,
      );
      expect(compared, isTrue);
      expect(
        saga.resume(migrationId: 'mig-happy'),
        OfficialLegacyMigrationResumeAction.atomicOwnerSwitch,
      );

      saga.freezeLegacyWriter(migrationId: 'mig-happy', nowMillis: 70);
      await saga.atomicOwnerSwitch(
        migrationId: 'mig-happy',
        officialMutationCountAtCutover: 0,
        nowMillis: 80,
      );
      expect(dao.findById('mig-happy')!.recordedKind, 'official');

      final smoked = await saga.smokeOfficialReview(
        migrationId: 'mig-happy',
        smokeAction: () async => true,
        nowMillis: 90,
      );
      expect(smoked, isTrue);

      saga.markLegacyShadowCleanupAfterRelease(
        migrationId: 'mig-happy',
        nowMillis: 100,
      );
      final done = dao.findById('mig-happy')!;
      expect(done.state, LegacyAnkiMigrationState.completed);
      expect(
        OfficialLegacySourceMigrationSaga.isCleanupAfterReleaseMarked(done),
        isTrue,
      );
      expect(
        saga.resume(migrationId: 'mig-happy'),
        OfficialLegacyMigrationResumeAction.done,
      );
      saga.releaseLease();
      expect(coordinator.phase, OfficialAnkiOperationPhase.idle);
    });

    test('resume after kill mid-pipeline continues from journal state', () async {
      saga.beginFromCleanLegacyCensus(
        migrationId: 'mig-resume',
        profileId: 'profile-w8-test01',
        legacyImportId: 'legacy-resume',
        sourceHash: 'hash-resume',
        policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
        policyConfirmedByUser: true,
        losslessScheduleMapAvailable: true,
        legacyCardCount: 1,
        nowMillis: 1,
      );

      // Simulate kill after backup recorded: walk to backingUp then release.
      dao.transition(
        migrationId: 'mig-resume',
        expected: LegacyAnkiMigrationState.awaitingPackage,
        next: LegacyAnkiMigrationState.validatingSource,
        nowMillis: 2,
      );
      dao.transition(
        migrationId: 'mig-resume',
        expected: LegacyAnkiMigrationState.validatingSource,
        next: LegacyAnkiMigrationState.backingUp,
        nowMillis: 3,
      );
      saga.releaseLease();

      // New saga instance = process restart.
      final resumed = OfficialLegacySourceMigrationSaga(
        dao: dao,
        coordinator: OfficialAnkiOperationCoordinator(),
        backupService: const _NoopBackupService(),
      );
      expect(
        resumed.resume(migrationId: 'mig-resume'),
        OfficialLegacyMigrationResumeAction.importOrReconstruct,
      );

      await resumed.importOrReconstruct(
        migrationId: 'mig-resume',
        packagePath: '${tmp.path}/x.apkg',
        importer: _FakeImporter(
          sources: OfficialAnkiSourceDao(db),
          sourceId: 'src-resume',
        ),
        nowMillis: 4,
      );
      expect(dao.findById('mig-resume')!.officialSourceId, 'src-resume');
      expect(
        resumed.resume(migrationId: 'mig-resume'),
        OfficialLegacyMigrationResumeAction.chooseSchedulingPolicy,
      );
    });
  });

  group('rollback', () {
    test('pre-switch rollback restores Legacy journal ownership', () async {
      saga.beginFromCleanLegacyCensus(
        migrationId: 'mig-rb-pre',
        profileId: 'profile-w8-test01',
        legacyImportId: 'legacy-rb-pre',
        sourceHash: 'h',
        policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
        policyConfirmedByUser: true,
        losslessScheduleMapAvailable: true,
        nowMillis: 1,
      );
      _ensureSource(db, sourceId: 'src-rb');
      // Advance to projectingCourse without full pipeline.
      for (final step in [
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
      ]) {
        dao.transition(
          migrationId: 'mig-rb-pre',
          expected: step.$1,
          next: step.$2,
          nowMillis: 2,
          officialSourceId: 'src-rb',
        );
      }

      saga.rollback(
        migrationId: 'mig-rb-pre',
        currentState: LegacyAnkiMigrationState.projectingCourse,
        nowMillis: 3,
      );
      final row = dao.findById('mig-rb-pre')!;
      expect(row.state, LegacyAnkiMigrationState.rolledBackLegacy);
      expect(row.recordedKind, 'legacy');
    });

    test('post-switch mutation=0 is UI rollback only (no dual-write)', () async {
      saga.beginFromCleanLegacyCensus(
        migrationId: 'mig-rb-post',
        profileId: 'profile-w8-test01',
        legacyImportId: 'legacy-rb-post',
        sourceHash: 'h2',
        policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
        policyConfirmedByUser: true,
        losslessScheduleMapAvailable: true,
        nowMillis: 1,
      );
      _ensureSource(db, sourceId: 'src-post');
      const chain = [
        LegacyAnkiMigrationState.awaitingPackage,
        LegacyAnkiMigrationState.validatingSource,
        LegacyAnkiMigrationState.backingUp,
        LegacyAnkiMigrationState.importingOfficial,
        LegacyAnkiMigrationState.indexingOfficial,
        LegacyAnkiMigrationState.mappingCards,
        LegacyAnkiMigrationState.projectingCourse,
        LegacyAnkiMigrationState.verifying,
        LegacyAnkiMigrationState.cutoverReady,
        LegacyAnkiMigrationState.cutover,
        LegacyAnkiMigrationState.observing,
      ];
      var current = LegacyAnkiMigrationState.awaitingPackage;
      // begin left us at awaitingPackage
      for (var i = 0; i < chain.length - 1; i++) {
        dao.transition(
          migrationId: 'mig-rb-post',
          expected: chain[i],
          next: chain[i + 1],
          nowMillis: 2 + i,
          officialSourceId: 'src-post',
        );
        current = chain[i + 1];
      }
      dao.setRecordedKind(
        migrationId: 'mig-rb-post',
        recordedKind: 'official',
        nowMillis: 100,
      );
      dao.setOfficialMutationCountAtCutover(
        migrationId: 'mig-rb-post',
        count: 0,
        nowMillis: 101,
      );

      saga.rollback(
        migrationId: 'mig-rb-post',
        currentState: current,
        officialMutationDelta: 0,
        nowMillis: 102,
      );
      final row = dao.findById('mig-rb-post')!;
      expect(row.state, LegacyAnkiMigrationState.rollbackEligible);
      // recordedKind flipped for UI, but dual-write must not resume — callers
      // still treat post-cutover Official mutation path as closed.
      expect(row.recordedKind, 'legacy');
    });

    test('post-switch mutation>0 refuses Legacy schedule rollback', () {
      saga.beginFromCleanLegacyCensus(
        migrationId: 'mig-rb-mut',
        profileId: 'profile-w8-test01',
        legacyImportId: 'legacy-rb-mut',
        sourceHash: 'h3',
        policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
        policyConfirmedByUser: true,
        losslessScheduleMapAvailable: true,
        nowMillis: 1,
      );
      _ensureSource(db, sourceId: 'src-mut');
      const chain = [
        LegacyAnkiMigrationState.awaitingPackage,
        LegacyAnkiMigrationState.validatingSource,
        LegacyAnkiMigrationState.backingUp,
        LegacyAnkiMigrationState.importingOfficial,
        LegacyAnkiMigrationState.indexingOfficial,
        LegacyAnkiMigrationState.mappingCards,
        LegacyAnkiMigrationState.projectingCourse,
        LegacyAnkiMigrationState.verifying,
        LegacyAnkiMigrationState.cutoverReady,
        LegacyAnkiMigrationState.cutover,
      ];
      for (var i = 0; i < chain.length - 1; i++) {
        dao.transition(
          migrationId: 'mig-rb-mut',
          expected: chain[i],
          next: chain[i + 1],
          nowMillis: 2 + i,
          officialSourceId: 'src-mut',
        );
      }

      saga.rollback(
        migrationId: 'mig-rb-mut',
        currentState: LegacyAnkiMigrationState.cutover,
        officialMutationDelta: 3,
        nowMillis: 50,
      );
      expect(
        dao.findById('mig-rb-mut')!.state,
        LegacyAnkiMigrationState.noLegacyScheduleRollback,
      );
    });
  });

  group('keepLegacyReadOnly', () {
    test('explicit policy abandons cutover without Official import', () async {
      saga.beginFromCleanLegacyCensus(
        migrationId: 'mig-keep',
        profileId: 'profile-w8-test01',
        legacyImportId: 'legacy-keep',
        sourceHash: 'hk',
        policy: LegacyAnkiSchedulingPolicy.keepLegacyReadOnly,
        policyConfirmedByUser: true,
        losslessScheduleMapAvailable: false,
        nowMillis: 1,
      );
      expect(
        saga.resume(migrationId: 'mig-keep'),
        OfficialLegacyMigrationResumeAction.keepLegacyReadOnlyTerminal,
      );
      await saga.chooseSchedulingPolicy(
        migrationId: 'mig-keep',
        policy: LegacyAnkiSchedulingPolicy.keepLegacyReadOnly,
        policyConfirmedByUser: true,
        losslessScheduleMapAvailable: false,
        nowMillis: 2,
      );
      expect(
        dao.findById('mig-keep')!.state,
        LegacyAnkiMigrationState.needsUserAction,
      );
      expect(
        () => saga.importOrReconstruct(
          migrationId: 'mig-keep',
          packagePath: 'x',
          importer: _FakeImporter(sources: OfficialAnkiSourceDao(db)),
        ),
        throwsA(isA<OfficialAnkiException>()),
      );
    });
  });

  test('rejects non-cleanLegacy census status', () {
    expect(
      () => saga.beginFromCleanLegacyCensus(
        migrationId: 'mig-bad',
        profileId: 'profile-w8-test01',
        legacyImportId: 'x',
        sourceHash: 'h',
        policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
        policyConfirmedByUser: true,
        censusStatus: 'ownerMismatch',
        losslessScheduleMapAvailable: true,
        nowMillis: 1,
      ),
      throwsA(isA<OfficialAnkiException>()),
    );
  });

  group('atomicOwnerSwitch and freezeLegacyWriter (R2)', () {
    void advanceToCutoverReady(String migrationId) {
      _ensureSource(db, sourceId: 'src-$migrationId');
      dao.insertDetected(
        migrationId: migrationId,
        profileId: 'profile-w8-test01',
        legacyImportId: 'legacy-$migrationId',
        policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
        nowMillis: 1,
      );
      const chain = [
        LegacyAnkiMigrationState.detected,
        LegacyAnkiMigrationState.awaitingPackage,
        LegacyAnkiMigrationState.validatingSource,
        LegacyAnkiMigrationState.backingUp,
        LegacyAnkiMigrationState.importingOfficial,
        LegacyAnkiMigrationState.indexingOfficial,
        LegacyAnkiMigrationState.mappingCards,
        LegacyAnkiMigrationState.projectingCourse,
        LegacyAnkiMigrationState.verifying,
        LegacyAnkiMigrationState.cutoverReady,
      ];
      for (var i = 0; i < chain.length - 1; i++) {
        dao.transition(
          migrationId: migrationId,
          expected: chain[i],
          next: chain[i + 1],
          nowMillis: 2 + i,
          officialSourceId: 'src-$migrationId',
        );
      }
    }

    test('atomicOwnerSwitch sets state cutover and recordedKind official atomically', () async {
      advanceToCutoverReady('mig-atomic-1');

      var onCutoverCalled = false;
      await saga.atomicOwnerSwitch(
        migrationId: 'mig-atomic-1',
        officialMutationCountAtCutover: 5,
        onCutover: () {
          onCutoverCalled = true;
        },
        nowMillis: 10,
      );

      expect(onCutoverCalled, isTrue);
      final row = dao.findById('mig-atomic-1')!;
      expect(row.state, LegacyAnkiMigrationState.cutover);
      expect(row.recordedKind, 'official');
      expect(row.officialMutationCountAtCutover, 5);
    });

    test('atomicOwnerSwitch rolls back completely if onCutover fails (no half-cutover)', () async {
      advanceToCutoverReady('mig-atomic-fail');

      expect(
        () => saga.atomicOwnerSwitch(
          migrationId: 'mig-atomic-fail',
          officialMutationCountAtCutover: 5,
          onCutover: () {
            throw StateError('simulated course database failure');
          },
          nowMillis: 10,
        ),
        throwsA(isA<StateError>()),
      );

      final row = dao.findById('mig-atomic-fail')!;
      // Must remain in cutoverReady with NO official recordedKind
      expect(row.state, LegacyAnkiMigrationState.cutoverReady);
      expect(row.recordedKind, isNot('official'));
    });
  });
}
