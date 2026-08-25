import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_source_reconciler.dart';
import 'package:turna/application/anki_official/migration/official_legacy_migration_coordinator.dart';
import 'package:turna/application/anki_official/migration/official_legacy_source_migration_saga.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/anki_owner_authority_dao.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

class _UnusedImporter implements OfficialAnkiImporter {
  @override
  Future<OfficialAnkiImportResult> importFile({
    required String packagePath,
    required String displayName,
    String? requestId,
    bool cancel = false,
  }) {
    throw StateError('the read-only policy must not import');
  }
}

const _flags = OfficialAnkiFeatureFlags(
  engine: true,
  import: true,
  catalogReady: true,
  runtimeCapable: true,
  platformReady: true,
  projection: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase course;
  late OfficialAnkiDatabase catalog;
  late Directory temp;
  late OfficialLegacyMigrationCoordinator coordinator;

  const evidence = OfficialAnkiSourceEvidence(
    profileId: 'profile-default-01',
    importId: 'legacy-a',
    sourceHash: 'hash-a',
    recordedOwner: OfficialAnkiPersistedOwner.legacy,
    legacyImportPresent: true,
    legacyNoteCount: 1,
    legacyCardCount: 1,
    legacySrsCount: 1,
  );
  final row = OfficialAnkiSourceCensusRow(
    evidence: evidence,
    decision: OfficialAnkiSourceReconcileDecision(
      state: OfficialAnkiSourceReconcileState.cleanLegacy,
      autoAction: OfficialAnkiReconcileAutoAction.queueMigration,
      evidenceHash: evidence.evidenceHash(),
      intendedOwner: OfficialAnkiPersistedOwner.legacy,
    ),
  );

  setUp(() async {
    course = CourseDatabase(NativeDatabase.memory());
    catalog = OfficialAnkiDatabase.memory();
    temp = Directory.systemTemp.createTempSync('official-w8-test-');
    final paths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: temp,
    );
    await paths.ensureLayout();
    coordinator = OfficialLegacyMigrationCoordinator(
      course: course,
      catalog: catalog,
      paths: paths,
      importer: _UnusedImporter(),
      engine: FakeOfficialAnkiEngine(),
      flags: _flags,
    );
  });

  Future<String> seedCommittedOwner({
    required String migrationId,
    bool mirrorCommitted = true,
  }) async {
    const sourceId = 'src-forward-recovery';
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: sourceId,
      profileId: 'profile-default-01',
      sourceHash: 'hash-forward',
      sourceSize: 1,
      displayName: 'Forward recovery fixture',
      state: 'active',
      backendCommit: 'test',
      nowMillis: 1,
    );
    final migrationDao = OfficialAnkiMigrationDao(catalog);
    migrationDao.insertDetected(
      migrationId: migrationId,
      profileId: 'profile-default-01',
      legacyImportId: 'legacy-forward',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      sourceHash: 'hash-forward',
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
    for (var index = 0; index < chain.length - 1; index++) {
      migrationDao.transition(
        migrationId: migrationId,
        expected: chain[index],
        next: chain[index + 1],
        nowMillis: index + 2,
        officialSourceId: sourceId,
      );
    }

    final authority = AnkiOwnerAuthorityDao(course);
    final courseId =
        CardIntroductionEligibility.courseIdForOfficialSource(sourceId);
    await authority.upsertSource(
      courseId: courseId,
      profileId: 'profile-default-01',
      sourceId: sourceId,
      backendKind: 'legacyTurna',
      displayName: 'Forward recovery fixture',
      sourceHash: 'hash-forward',
      sourceFingerprint: 'fp-forward',
      state: AnkiSourceVisibility.active,
    );
    await authority.beginTransition(
      transitionId: 'tr-$migrationId',
      profileId: 'profile-default-01',
      legacyImportId: 'legacy-forward',
      officialSourceId: sourceId,
      courseId: courseId,
      fromBackend: 'legacyTurna',
      toBackend: 'official',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling.name,
    );
    const phases = [
      OwnerTransitionPhase.discovered,
      OwnerTransitionPhase.awaitingUserPolicy,
      OwnerTransitionPhase.backingUp,
      OwnerTransitionPhase.importingOfficial,
      OwnerTransitionPhase.verifyingIdentity,
      OwnerTransitionPhase.projectionStaging,
      OwnerTransitionPhase.cutoverReady,
      OwnerTransitionPhase.frozen,
      OwnerTransitionPhase.committing,
    ];
    for (var index = 0; index < phases.length - 1; index++) {
      await authority.advancePhase(
        transitionId: 'tr-$migrationId',
        from: phases[index],
        to: phases[index + 1],
      );
    }
    await authority.compareAndSetWriteFence(
      courseId: courseId,
      expected: AnkiWriteFence.open,
      next: AnkiWriteFence.frozen,
    );
    await authority.commitOwnership(
      transitionId: 'tr-$migrationId',
      courseId: courseId,
    );
    if (mirrorCommitted) {
      migrationDao.atomicCutoverTransition(
        migrationId: migrationId,
        officialMutationCountAtCutover: 0,
        nowMillis: 20,
      );
    }
    return sourceId;
  }

  tearDown(() async {
    catalog.close();
    await course.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('unconfirmed scheduling policy creates no journal or owner row',
      () async {
    await expectLater(
      coordinator.run(
        censusRow: row,
        package: File('${temp.path}/unused.apkg'),
        policy: LegacyAnkiSchedulingPolicy.resetAsNew,
        policyConfirmedByUser: false,
      ),
      throwsA(anything),
    );

    expect(
      OfficialAnkiMigrationDao(catalog)
          .listMigrations(profileId: 'profile-default-01'),
      isEmpty,
    );
    expect(
      await AnkiOwnerAuthorityDao(course).listSources('profile-default-01'),
      isEmpty,
    );
  });

  test('keep Legacy read-only journals the choice without importing', () async {
    final result = await coordinator.run(
      censusRow: row,
      package: File('${temp.path}/unused.apkg'),
      policy: LegacyAnkiSchedulingPolicy.keepLegacyReadOnly,
      policyConfirmedByUser: true,
    );

    expect(result.outcome, OfficialLegacyMigrationOutcome.keptLegacyReadOnly);
    expect(result.state, LegacyAnkiMigrationState.needsUserAction);
    expect(
      await AnkiOwnerAuthorityDao(course).listSources('profile-default-01'),
      isEmpty,
      reason: 'export/read-only policy must not prepare an Official owner',
    );
  });

  test('CourseDB commit gap replays catalog mirror without a second commit',
      () async {
    await seedCommittedOwner(
      migrationId: 'mig-mirror-gap',
      mirrorCommitted: false,
    );
    final saga = OfficialLegacySourceMigrationSaga(
      dao: OfficialAnkiMigrationDao(catalog),
      coordinator: OfficialAnkiOperationCoordinator(),
      authorityDao: AnkiOwnerAuthorityDao(course),
    );

    await saga.atomicOwnerSwitch(migrationId: 'mig-mirror-gap');

    expect(
      OfficialAnkiMigrationDao(catalog).findById('mig-mirror-gap')!.state,
      LegacyAnkiMigrationState.cutover,
    );
    expect(
      (await AnkiOwnerAuthorityDao(course).transitionById('tr-mig-mirror-gap'))!
          .phase,
      OwnerTransitionPhase.observing,
    );
  });

  test('post-commit smoke failure recovers forward and closes transition',
      () async {
    await seedCommittedOwner(migrationId: 'mig-forward');
    final migrationDao = OfficialAnkiMigrationDao(catalog);
    final authority = AnkiOwnerAuthorityDao(course);
    final saga = OfficialLegacySourceMigrationSaga(
      dao: migrationDao,
      coordinator: OfficialAnkiOperationCoordinator(),
      authorityDao: authority,
    );

    expect(
      await saga.smokeOfficialReview(
        migrationId: 'mig-forward',
        smokeAction: () async => false,
      ),
      isFalse,
    );
    expect(
      (await authority.transitionById('tr-mig-forward'))!.phase,
      OwnerTransitionPhase.recoveringForward,
    );
    expect(
      migrationDao.findById('mig-forward')!.state,
      LegacyAnkiMigrationState.failedRecoverable,
    );

    await saga.recoverForwardMirror(migrationId: 'mig-forward');
    expect(
      await saga.smokeOfficialReview(
        migrationId: 'mig-forward',
        smokeAction: () async => true,
      ),
      isTrue,
    );
    await saga.markLegacyShadowCleanupAfterRelease(
      migrationId: 'mig-forward',
    );

    expect(
      migrationDao.findById('mig-forward')!.state,
      LegacyAnkiMigrationState.completed,
    );
    expect(
      (await authority.transitionById('tr-mig-forward'))!.phase,
      OwnerTransitionPhase.complete,
    );
    final owner = await authority.findByCourseId(
      CardIntroductionEligibility.courseIdForOfficialSource(
        'src-forward-recovery',
      ),
    );
    expect(owner!.isOfficialBackend, isTrue);
    expect(owner.writeFence, AnkiWriteFence.officialOnly);
  });

  test('rollback refuses a CourseDB owner already committed Official',
      () async {
    await seedCommittedOwner(
      migrationId: 'mig-no-rollback',
      mirrorCommitted: false,
    );

    await expectLater(
      coordinator.rollbackBeforeOwnerCommit('mig-no-rollback'),
      throwsA(
        isA<OfficialAnkiException>().having(
          (error) => error.messageKey,
          'messageKey',
          'official_anki.forward_recovery_required',
        ),
      ),
    );
  });
}
