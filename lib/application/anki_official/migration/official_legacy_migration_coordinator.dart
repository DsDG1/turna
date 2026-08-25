import 'dart:io';

import 'package:drift/drift.dart';
import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/application/anki/unified_anki_import_orchestrator.dart';
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

  Future<OfficialLegacyMigrationResult> run({
    required OfficialAnkiSourceCensusRow censusRow,
    required File package,
    required LegacyAnkiSchedulingPolicy policy,
    required bool policyConfirmedByUser,
  }) async {
    if (!policyConfirmedByUser) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.scheduling_policy_requires_user_choice',
      );
    }
    final resolvedImporter = importer;
    final resolvedEngine = engine;
    if (!policy.abandonsOfficialCutover &&
        (!flags.allowsOfficialImport || !flags.allowsProjection)) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.flag_fail_closed',
      );
    }
    if (!policy.abandonsOfficialCutover &&
        (resolvedImporter == null || resolvedEngine == null)) {
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

    final dao = OfficialAnkiMigrationDao(catalog);
    final saga = OfficialLegacySourceMigrationSaga(
      dao: dao,
      coordinator: operations,
      authorityDao: AnkiOwnerAuthorityDao(course),
    );
    const driver = OfficialLegacyMigrationDriver();
    var row = dao.findByLegacyImport(
      profileId: evidence.profileId,
      legacyImportId: importId,
    );
    try {
      if (row == null) {
        driver.beginOne(
          saga: saga,
          row: censusRow,
          policy: policy,
          policyConfirmedByUser: policyConfirmedByUser,
        );
        row = dao.findByLegacyImport(
          profileId: evidence.profileId,
          legacyImportId: importId,
        )!;
      } else {
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
        row = dao.findById(row.migrationId)!;
      }

      if (policy.abandonsOfficialCutover) {
        await saga.chooseSchedulingPolicy(
          migrationId: row.migrationId,
          policy: policy,
          policyConfirmedByUser: policyConfirmedByUser,
          losslessScheduleMapAvailable: false,
        );
        final terminal = dao.findById(row.migrationId)!;
        return OfficialLegacyMigrationResult(
          outcome: OfficialLegacyMigrationOutcome.keptLegacyReadOnly,
          migrationId: terminal.migrationId,
          state: terminal.state,
        );
      }

      final legacyCards = await DatabaseLegacyAnkiCensusReader(course)
          .loadCardIdentities(importId);
      row = dao.findById(row.migrationId)!;
      if (row.state == LegacyAnkiMigrationState.awaitingPackage ||
          row.state == LegacyAnkiMigrationState.validatingSource) {
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

      row = dao.findById(row.migrationId)!;
      if (row.state == LegacyAnkiMigrationState.backingUp) {
        await saga.importOrReconstruct(
          migrationId: row.migrationId,
          packagePath: package.path,
          importer: resolvedImporter!,
          displayName: package.uri.pathSegments.last,
        );
      } else if (row.state == LegacyAnkiMigrationState.importingOfficial) {
        // The Official importer owns its own crash journal. Repeating the
        // same-hash import resumes/indexes and returns the stable source id.
        final recovered = await resolvedImporter!.importFile(
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

      row = dao.findById(row.migrationId)!;
      await saga.chooseSchedulingPolicy(
        migrationId: row.migrationId,
        policy: policy,
        policyConfirmedByUser: policyConfirmedByUser,
        losslessScheduleMapAvailable: false,
      );

      final sourceId = row.officialSourceId ??
          dao.findById(row.migrationId)!.officialSourceId;
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
      row = dao.findById(row.migrationId)!;
      if (policy == LegacyAnkiSchedulingPolicy.resetAsNew &&
          row.state == LegacyAnkiMigrationState.indexingOfficial) {
        for (var offset = 0; offset < sourceCards.length; offset += 10000) {
          final end = offset + 10000 < sourceCards.length
              ? offset + 10000
              : sourceCards.length;
          final batch = [
            for (final card in sourceCards.sublist(offset, end)) card.cardId,
          ];
          final reset = await resolvedEngine!.scheduleCardsAsNew(batch);
          if (reset != batch.length) {
            throw OfficialAnkiException(
              code: OfficialAnkiErrorCode.invalidState,
              messageKey: 'official_anki.schedule_reset_incomplete',
              debugDetails: '$reset/${batch.length}',
            );
          }
        }
      }

      final officialCards = [
        for (final card in sourceCards)
          OfficialAnkiCardIdentity(
            officialCardId: card.cardId,
            templateOrd: card.templateOrd,
            officialNoteId: card.noteId,
            noteGuid: card.noteGuid,
          ),
      ];
      var projectionItemCount = 0;
      row = dao.findById(row.migrationId)!;
      if (row.state == LegacyAnkiMigrationState.indexingOfficial ||
          row.state == LegacyAnkiMigrationState.mappingCards ||
          row.state == LegacyAnkiMigrationState.projectingCourse) {
        final mapped = await saga.mapCardsAndProject(
          migrationId: row.migrationId,
          legacyCards: legacyCards,
          officialCards: officialCards,
          sameTrustedPackage: true,
          projectionAction: () async {
            final projection = OfficialAnkiCourseProjectionService(
              engine: resolvedEngine!,
              catalog: catalog,
              course: course,
              sourceId: sourceId,
              profileId: paths.profileId,
              flags: flags,
            );
            final published = await projection.projectSource();
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
          final paused = dao.findById(row.migrationId)!;
          if (paused.state != LegacyAnkiMigrationState.needsUserAction) {
            throw OfficialAnkiException(
              code: OfficialAnkiErrorCode.invalidState,
              messageKey:
                  paused.state == LegacyAnkiMigrationState.failedRecoverable
                      ? 'official_anki.projection_failed'
                      : 'official_anki.migration_paused',
            );
          }
          return OfficialLegacyMigrationResult(
            outcome: OfficialLegacyMigrationOutcome.awaitingMapping,
            migrationId: paused.migrationId,
            state: paused.state,
            officialSourceId: sourceId,
          );
        }
      }

      row = dao.findById(row.migrationId)!;
      if (row.state == LegacyAnkiMigrationState.verifying) {
        if (projectionItemCount == 0) {
          projectionItemCount = (await course.customSelect(
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
          projectionItemCount: projectionItemCount,
          matchedCount: legacyCards.length,
        );
        if (!verified) {
          throw const OfficialAnkiException(
            code: OfficialAnkiErrorCode.invalidState,
            messageKey: 'official_anki.verify_count_mismatch',
          );
        }
      }

      row = dao.findById(row.migrationId)!;
      if (row.state == LegacyAnkiMigrationState.cutoverReady) {
        await saga.freezeLegacyWriter(migrationId: row.migrationId);
        await saga.atomicOwnerSwitch(migrationId: row.migrationId);
      }
      row = dao.findById(row.migrationId)!;
      if (row.state == LegacyAnkiMigrationState.cutover) {
        await UnifiedAnkiImportOrchestrator.instance.publishFromProjection(
          sourceId: sourceId,
          sourceHash: sourceHash,
        );
        final smokeOk = await saga.smokeOfficialReview(
          migrationId: row.migrationId,
          smokeAction: () async {
            final descriptor = await resolvedEngine!
                .getCardDescriptorsBatch([sourceCards.first.cardId]);
            if (descriptor.length != 1) return false;
            await resolvedEngine.renderCard(
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
      row = dao.findById(row.migrationId)!;
      if (row.state == LegacyAnkiMigrationState.observing) {
        await saga.markLegacyShadowCleanupAfterRelease(
          migrationId: row.migrationId,
        );
      }
      final completed = dao.findById(row.migrationId)!;
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
}
