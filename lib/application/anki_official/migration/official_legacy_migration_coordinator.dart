import 'dart:io';

import 'package:drift/drift.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_eligibility.dart';
import 'package:turna/application/anki_official/import/unified_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_census.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_source_reconciler.dart';
import 'package:turna/application/anki_official/migration/official_legacy_migration_driver.dart';
import 'package:turna/application/anki_official/migration/official_legacy_source_migration_saga.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/anki_owner_authority_dao.dart';
import 'package:turna/data/course_database.dart';

enum OfficialLegacyMigrationOutcome {
  completed,
  awaitingMapping,
  keptLegacyReadOnly,
}

class OfficialLegacyMigrationResult {
  const OfficialLegacyMigrationResult({
    required this.outcome,
    required this.migrationId,
    required this.state,
    this.officialSourceId,
  });

  final OfficialLegacyMigrationOutcome outcome;
  final String migrationId;
  final LegacyAnkiMigrationState state;
  final String? officialSourceId;
}

/// Production W8 executor for exactly one census-classified Legacy source.
///
/// The method is deliberately journal-driven. Repeating it after a crash
/// resumes from the persisted state; owner commit happens only after package
/// hash, identity, projection, cardinality, and explicit scheduling policy
/// gates have passed.
class OfficialLegacyMigrationCoordinator {
  OfficialLegacyMigrationCoordinator({
    required this.course,
    required this.catalog,
    required this.paths,
    this.importer,
    this.engine,
    OfficialAnkiOperationCoordinator? operations,
    OfficialAnkiFeatureFlags? flags,
  })  : operations = operations ?? OfficialAnkiOperationCoordinator(),
        flags = flags ?? OfficialAnkiFeatureFlags.current;

  final CourseDatabase course;
  final OfficialAnkiDatabase catalog;
  final OfficialAnkiPaths paths;
  final OfficialAnkiImporter? importer;
  final OfficialAnkiEngine? engine;
  final OfficialAnkiOperationCoordinator operations;
  final OfficialAnkiFeatureFlags flags;

  Future<void> rollbackBeforeOwnerCommit(String migrationId) async {
    final dao = OfficialAnkiMigrationDao(catalog);
    final row = dao.findById(migrationId);
    if (row == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.migration_missing',
      );
    }
    if (row.state == LegacyAnkiMigrationState.cutover ||
        row.state == LegacyAnkiMigrationState.observing ||
        row.state == LegacyAnkiMigrationState.completed) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.forward_recovery_required',
      );
    }
    final authority = AnkiOwnerAuthorityDao(course);
    final transition = await authority.transitionById('tr-$migrationId');
    if (transition != null) {
      final source = await authority.findByCourseId(transition.courseId);
      if (source?.isOfficialBackend == true ||
          source?.writeFence == AnkiWriteFence.officialOnly ||
          transition.phase == OwnerTransitionPhase.recoveringForward) {
        throw const OfficialAnkiException(
          code: OfficialAnkiErrorCode.invalidState,
          messageKey: 'official_anki.forward_recovery_required',
        );
      }
    }
    if (transition != null && !transition.phase.isTerminal) {
      await authority.advancePhase(
        transitionId: transition.transitionId,
        from: transition.phase,
        to: OwnerTransitionPhase.rollbackPending,
      );
      await authority.rollbackToLegacy(
        transitionId: transition.transitionId,
        courseId: transition.courseId,
      );
    }
    final saga = OfficialLegacySourceMigrationSaga(
      dao: dao,
      coordinator: operations,
      authorityDao: authority,
    );
    const OfficialLegacyMigrationDriver().rollbackOne(
      saga: saga,
      migrationId: migrationId,
    );
  }

  /// Re-read the migration row we already hold. run() re-reads after every
  /// saga step because the saga and driver transition the journal without
  /// handing the new row back; this keeps that explicit and single-sourced.
  LegacyAnkiMigrationRow _reload(
    OfficialAnkiMigrationDao dao,
    LegacyAnkiMigrationRow row,
  ) =>
      dao.findById(row.migrationId)!;

  Future<OfficialLegacyMigrationResult> run({
    required OfficialAnkiSourceCensusRow censusRow,
    required File package,
    required LegacyAnkiSchedulingPolicy policy,
    required bool policyConfirmedByUser,
  }) async {
    final identity = _preflight(
      censusRow: censusRow,
      policy: policy,
      policyConfirmedByUser: policyConfirmedByUser,
    );
    final dao = OfficialAnkiMigrationDao(catalog);
    final saga = OfficialLegacySourceMigrationSaga(
      dao: dao,
      coordinator: operations,
      authorityDao: AnkiOwnerAuthorityDao(course),
    );
    final initialRow = dao.findByLegacyImport(
      profileId: censusRow.evidence.profileId,
      legacyImportId: identity.importId,
    );
    try {
      var row = await _beginOrResumeRow(
        dao: dao,
        saga: saga,
        censusRow: censusRow,
        policy: policy,
        policyConfirmedByUser: policyConfirmedByUser,
        importId: identity.importId,
        row: initialRow,
      );

      if (policy.abandonsOfficialCutover) {
        return await _keptLegacyReadOnly(
          dao: dao,
          saga: saga,
          row: row,
          policy: policy,
          policyConfirmedByUser: policyConfirmedByUser,
        );
      }

      final legacyCards = await DatabaseLegacyAnkiCensusReader(course)
          .loadCardIdentities(identity.importId);
      row = _reload(dao, row);
      await _backupIfNeeded(
        dao: dao,
        saga: saga,
        row: row,
        package: package,
        sourceHash: identity.sourceHash,
        legacyCards: legacyCards,
      );

      row = _reload(dao, row);
      await _importOrReconstruct(
        dao: dao,
        saga: saga,
        row: row,
        package: package,
      );

      row = _reload(dao, row);
      await saga.chooseSchedulingPolicy(
        migrationId: row.migrationId,
        policy: policy,
        policyConfirmedByUser: policyConfirmedByUser,
        losslessScheduleMapAvailable: false,
      );

      final (sourceId, sourceCards) = _resolveOfficialSource(
        dao: dao,
        row: row,
        sourceHash: identity.sourceHash,
      );
      row = _reload(dao, row);
      await _resetAsNewIfNeeded(
        row: row,
        policy: policy,
        sourceCards: sourceCards,
      );

      final officialCards = [
        for (final card in sourceCards)
          OfficialAnkiCardIdentity(
            officialCardId: card.cardId,
            templateOrd: card.templateOrd,
            officialNoteId: card.noteId,
            noteGuid: card.noteGuid,
          ),
      ];
      row = _reload(dao, row);
      final projected = await _projectIfNeeded(
        dao: dao,
        saga: saga,
        row: row,
        legacyCards: legacyCards,
        officialCards: officialCards,
        sourceId: sourceId,
      );
      final pausedResult = projected.paused;
      if (pausedResult != null) {
        return pausedResult;
      }

      row = _reload(dao, row);
      await _verifyCardinalityIfNeeded(
        saga: saga,
        row: row,
        legacyCards: legacyCards,
        sourceCards: sourceCards,
        officialCards: officialCards,
        sourceId: sourceId,
        importId: identity.importId,
        projectionItemCount: projected.projectionItemCount,
      );

      row = _reload(dao, row);
      if (row.state == LegacyAnkiMigrationState.cutoverReady) {
        await saga.freezeLegacyWriter(migrationId: row.migrationId);
        await saga.atomicOwnerSwitch(migrationId: row.migrationId);
      }
      row = _reload(dao, row);
      if (row.state == LegacyAnkiMigrationState.cutover) {
        await _publishAndSmoke(
          saga: saga,
          row: row,
          sourceId: sourceId,
          sourceHash: identity.sourceHash,
          sourceCards: sourceCards,
        );
      }
      row = _reload(dao, row);
      if (row.state == LegacyAnkiMigrationState.observing) {
        await saga.markLegacyShadowCleanupAfterRelease(
          migrationId: row.migrationId,
        );
      }
      final completed = _reload(dao, row);
      return OfficialLegacyMigrationResult(
        outcome: OfficialLegacyMigrationOutcome.completed,
        migrationId: completed.migrationId,
        state: completed.state,
        officialSourceId: sourceId,
      );
    } finally {
      saga.releaseLease();
    }
  }

  /// Argument/capability gates that must all pass before the journal is
  /// touched. Returns the legacy identity the whole run is keyed on.
  ({String importId, String sourceHash}) _preflight({
    required OfficialAnkiSourceCensusRow censusRow,
    required LegacyAnkiSchedulingPolicy policy,
    required bool policyConfirmedByUser,
  }) {
    if (!policyConfirmedByUser) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.scheduling_policy_requires_user_choice',
      );
    }
    if (!policy.abandonsOfficialCutover &&
        (!flags.allowsOfficialImport || !flags.allowsProjection)) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.flag_fail_closed',
      );
    }
    if (!policy.abandonsOfficialCutover &&
        (importer == null || engine == null)) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.runtime_unavailable',
      );
    }
    final evidence = censusRow.evidence;
    final importId = evidence.importId ?? '';
    final sourceHash = evidence.sourceHash ?? '';
    if (importId.isEmpty || sourceHash.isEmpty) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.migration_missing_legacy_identity',
      );
    }
    return (importId: importId, sourceHash: sourceHash);
  }

  /// Fresh migration: begin the journal from the census row. Resume: verify
  /// the chosen policy still matches, take the migrating lease, and unwind
  /// the paused/failed state far enough to rerun the affected segment.
  Future<LegacyAnkiMigrationRow> _beginOrResumeRow({
    required OfficialAnkiMigrationDao dao,
    required OfficialLegacySourceMigrationSaga saga,
    required OfficialAnkiSourceCensusRow censusRow,
    required LegacyAnkiSchedulingPolicy policy,
    required bool policyConfirmedByUser,
    required String importId,
    required LegacyAnkiMigrationRow? row,
  }) async {
    if (row == null) {
      const OfficialLegacyMigrationDriver().beginOne(
        saga: saga,
        row: censusRow,
        policy: policy,
        policyConfirmedByUser: policyConfirmedByUser,
      );
      return dao.findByLegacyImport(
        profileId: censusRow.evidence.profileId,
        legacyImportId: importId,
      )!;
    }
    if (row.schedulingPolicy != policy) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.scheduling_policy_mismatch',
        debugDetails:
            'journal=${row.schedulingPolicy.name}, chosen=${policy.name}',
      );
    }
    operations.requireNotReviewing();
    operations.acquire(OfficialAnkiOperationPhase.migrating);
    if (row.state == LegacyAnkiMigrationState.failedRecoverable &&
        row.officialSourceId == null) {
      dao.transition(
        migrationId: row.migrationId,
        expected: row.state,
        next: LegacyAnkiMigrationState.awaitingPackage,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
      );
    } else if (row.state == LegacyAnkiMigrationState.failedRecoverable) {
      final sourceId = row.officialSourceId;
      final authority = AnkiOwnerAuthorityDao(course);
      final owner = sourceId == null
          ? null
          : await authority.findByCourseId(
              CardIntroductionEligibility.courseIdForOfficialSource(
                sourceId,
              ),
            );
      if (owner?.isOfficialBackend == true &&
          owner?.writeFence == AnkiWriteFence.officialOnly) {
        await saga.recoverForwardMirror(migrationId: row.migrationId);
      } else {
        dao.transition(
          migrationId: row.migrationId,
          expected: row.state,
          next: LegacyAnkiMigrationState.backingUp,
          nowMillis: DateTime.now().millisecondsSinceEpoch,
        );
      }
    } else if (row.state == LegacyAnkiMigrationState.needsUserAction &&
        !policy.abandonsOfficialCutover) {
      dao.transition(
        migrationId: row.migrationId,
        expected: row.state,
        next: row.officialSourceId == null
            ? LegacyAnkiMigrationState.awaitingPackage
            : LegacyAnkiMigrationState.mappingCards,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
      );
    }
    return _reload(dao, row);
  }

  /// Legacy-only policy: record the scheduling choice and stop before any
  /// cutover work.
  Future<OfficialLegacyMigrationResult> _keptLegacyReadOnly({
    required OfficialAnkiMigrationDao dao,
    required OfficialLegacySourceMigrationSaga saga,
    required LegacyAnkiMigrationRow row,
    required LegacyAnkiSchedulingPolicy policy,
    required bool policyConfirmedByUser,
  }) async {
    await saga.chooseSchedulingPolicy(
      migrationId: row.migrationId,
      policy: policy,
      policyConfirmedByUser: policyConfirmedByUser,
      losslessScheduleMapAvailable: false,
    );
    final terminal = _reload(dao, row);
    return OfficialLegacyMigrationResult(
      outcome: OfficialLegacyMigrationOutcome.keptLegacyReadOnly,
      migrationId: terminal.migrationId,
      state: terminal.state,
    );
  }

  /// Segment awaitingPackage/validatingSource: verify the picked package
  /// against the recorded hash and snapshot the legacy DB before import.
  Future<void> _backupIfNeeded({
    required OfficialAnkiMigrationDao dao,
    required OfficialLegacySourceMigrationSaga saga,
    required LegacyAnkiMigrationRow row,
    required File package,
    required String sourceHash,
    required List<LegacyAnkiCardIdentity> legacyCards,
  }) async {
    if (row.state != LegacyAnkiMigrationState.awaitingPackage &&
        row.state != LegacyAnkiMigrationState.validatingSource) {
      return;
    }
    final backedUp = await saga.snapshotAndBackup(
      migrationId: row.migrationId,
      pickedFile: package,
      expectedSourceHash: sourceHash,
      paths: paths,
      legacyCards: legacyCards,
    );
    if (!backedUp) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.packageInvalid,
        messageKey: 'official_anki.migration_package_mismatch',
      );
    }
  }

  /// Segment backingUp/importingOfficial. The Official importer owns its own
  /// crash journal: repeating the same-hash import resumes/indexes and
  /// returns the stable source id.
  Future<void> _importOrReconstruct({
    required OfficialAnkiMigrationDao dao,
    required OfficialLegacySourceMigrationSaga saga,
    required LegacyAnkiMigrationRow row,
    required File package,
  }) async {
    if (row.state == LegacyAnkiMigrationState.backingUp) {
      await saga.importOrReconstruct(
        migrationId: row.migrationId,
        packagePath: package.path,
        importer: importer!,
        displayName: package.uri.pathSegments.last,
      );
    } else if (row.state == LegacyAnkiMigrationState.importingOfficial) {
      final recovered = await importer!.importFile(
        packagePath: package.path,
        displayName: package.uri.pathSegments.last,
      );
      dao.transition(
        migrationId: row.migrationId,
        expected: LegacyAnkiMigrationState.importingOfficial,
        next: LegacyAnkiMigrationState.indexingOfficial,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
        officialSourceId: recovered.sourceId,
      );
    }
  }

  /// Resolve the official catalog source for the migration and require it to
  /// exist with cards — an empty catalog here means the import half never
  /// landed.
  (String, List<OfficialAnkiCardDescriptor>) _resolveOfficialSource({
    required OfficialAnkiMigrationDao dao,
    required LegacyAnkiMigrationRow row,
    required String sourceHash,
  }) {
    final sourceId = row.officialSourceId ?? _reload(dao, row).officialSourceId;
    if (sourceId == null || sourceId.isEmpty) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.catalog_missing',
      );
    }
    final sourceCards = OfficialAnkiSourceDao(catalog).listCardsForImport(
      sourceId: sourceId,
      profileId: paths.profileId,
      sourceHash: sourceHash,
    );
    if (sourceCards.isEmpty) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.source_cards_missing',
      );
    }
    return (sourceId, sourceCards);
  }

  /// Segment indexingOfficial + resetAsNew policy: push the whole card set
  /// through scheduleCardsAsNew in batches; a short reset fails the run.
  Future<void> _resetAsNewIfNeeded({
    required LegacyAnkiMigrationRow row,
    required LegacyAnkiSchedulingPolicy policy,
    required List<OfficialAnkiCardDescriptor> sourceCards,
  }) async {
    if (policy != LegacyAnkiSchedulingPolicy.resetAsNew ||
        row.state != LegacyAnkiMigrationState.indexingOfficial) {
      return;
    }
    for (var offset = 0; offset < sourceCards.length; offset += 10000) {
      final end = offset + 10000 < sourceCards.length
          ? offset + 10000
          : sourceCards.length;
      final batch = [
        for (final card in sourceCards.sublist(offset, end)) card.cardId,
      ];
      final reset = await engine!.scheduleCardsAsNew(batch);
      if (reset != batch.length) {
        throw OfficialAnkiException(
          code: OfficialAnkiErrorCode.invalidState,
          messageKey: 'official_anki.schedule_reset_incomplete',
          debugDetails: '$reset/${batch.length}',
        );
      }
    }
  }

  /// Segments indexingOfficial/mappingCards/projectingCourse: map the legacy
  /// cards onto official notes and run the projection. A pause means the
  /// user must confirm field mapping first; item count feeds verification.
  Future<({OfficialLegacyMigrationResult? paused, int projectionItemCount})>
      _projectIfNeeded({
    required OfficialAnkiMigrationDao dao,
    required OfficialLegacySourceMigrationSaga saga,
    required LegacyAnkiMigrationRow row,
    required List<LegacyAnkiCardIdentity> legacyCards,
    required List<OfficialAnkiCardIdentity> officialCards,
    required String sourceId,
  }) async {
    if (row.state != LegacyAnkiMigrationState.indexingOfficial &&
        row.state != LegacyAnkiMigrationState.mappingCards &&
        row.state != LegacyAnkiMigrationState.projectingCourse) {
      return (paused: null, projectionItemCount: 0);
    }
    var projectionItemCount = 0;
    final mapped = await saga.mapCardsAndProject(
      migrationId: row.migrationId,
      legacyCards: legacyCards,
      officialCards: officialCards,
      sameTrustedPackage: true,
      projectionAction: () async {
        final projection = OfficialAnkiCourseProjectionService(
          engine: engine!,
          catalog: catalog,
          course: course,
          sourceId: sourceId,
          profileId: paths.profileId,
          flags: flags,
        );
        final published = await projection.projectSource(
          notetypeIds: projection.catalogNotetypeIds(),
        );
        if (published.needsMapping) {
          throw const OfficialAnkiMigrationNeedsUserAction(
            'Confirm the source field mapping, then resume migration.',
          );
        }
        if (published.failed || published.cancelled) {
          throw OfficialAnkiException(
            code: OfficialAnkiErrorCode.invalidState,
            messageKey: 'official_anki.projection_failed',
            debugDetails: published.errorCode,
          );
        }
        projectionItemCount = published.itemCount;
      },
    );
    if (!mapped) {
      final paused = _reload(dao, row);
      if (paused.state != LegacyAnkiMigrationState.needsUserAction) {
        throw OfficialAnkiException(
          code: OfficialAnkiErrorCode.invalidState,
          messageKey:
              paused.state == LegacyAnkiMigrationState.failedRecoverable
                  ? 'official_anki.projection_failed'
                  : 'official_anki.migration_paused',
        );
      }
      return (
        paused: OfficialLegacyMigrationResult(
          outcome: OfficialLegacyMigrationOutcome.awaitingMapping,
          migrationId: paused.migrationId,
          state: paused.state,
          officialSourceId: sourceId,
        ),
        projectionItemCount: projectionItemCount,
      );
    }
    return (paused: null, projectionItemCount: projectionItemCount);
  }

  /// Segment verifying: compare legacy vs official cardinality (cards, notes,
  /// decks, projection items) and fail closed on any mismatch.
  Future<void> _verifyCardinalityIfNeeded({
    required OfficialLegacySourceMigrationSaga saga,
    required LegacyAnkiMigrationRow row,
    required List<LegacyAnkiCardIdentity> legacyCards,
    required List<OfficialAnkiCardDescriptor> sourceCards,
    required List<OfficialAnkiCardIdentity> officialCards,
    required String sourceId,
    required String importId,
    required int projectionItemCount,
  }) async {
    if (row.state != LegacyAnkiMigrationState.verifying) return;
    var projectionCount = projectionItemCount;
    if (projectionCount == 0) {
      projectionCount = (await course.customSelect(
        'SELECT COUNT(*) AS n FROM official_anki_projection_index '
        'WHERE source_id = ?',
        variables: [
          Variable.withString(sourceId),
        ],
      ).getSingle())
          .read<int>('n');
    }
    final legacyDecks = await course.customSelect(
      'SELECT COUNT(DISTINCT did) AS n FROM anki_cards_meta '
      'WHERE import_id = ?',
      variables: [Variable.withString(importId)],
    ).getSingle();
    final verified = await saga.compareCardinality(
      migrationId: row.migrationId,
      legacyCardCount: legacyCards.length,
      officialCardCount: officialCards.length,
      legacyNoteCount:
          legacyCards.map((card) => card.legacyNoteId).toSet().length,
      officialNoteCount:
          officialCards.map((card) => card.officialNoteId).toSet().length,
      legacyDeckCount: legacyDecks.read<int>('n'),
      officialDeckCount: officialCards.isEmpty
          ? 0
          : sourceCards.map((c) => c.deckId).toSet().length,
      projectionItemCount: projectionCount,
      matchedCount: legacyCards.length,
    );
    if (!verified) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.verify_count_mismatch',
      );
    }
  }

  /// Segment cutover: publish the projection into the app's data layer and
  /// smoke-test one card render before the migration may complete.
  Future<void> _publishAndSmoke({
    required OfficialLegacySourceMigrationSaga saga,
    required LegacyAnkiMigrationRow row,
    required String sourceId,
    required String sourceHash,
    required List<OfficialAnkiCardDescriptor> sourceCards,
  }) async {
    await UnifiedAnkiImportOrchestrator.instance.publishFromProjection(
      sourceId: sourceId,
      sourceHash: sourceHash,
    );
    final smokeOk = await saga.smokeOfficialReview(
      migrationId: row.migrationId,
      smokeAction: () async {
        final descriptor = await engine!
            .getCardDescriptorsBatch([sourceCards.first.cardId]);
        if (descriptor.length != 1) return false;
        await engine!.renderCard(
          cardId: sourceCards.first.cardId,
          browser: true,
        );
        return true;
      },
    );
    if (!smokeOk) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.smoke_failed',
      );
    }
  }
}
