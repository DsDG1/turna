import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_backup_manifest.dart';
import 'package:turna/application/anki_official/migration/official_anki_census.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_saga.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

/// Single-source fixture pilot Saga orchestrator.
/// Strictly limited to allowlist sources. Cutover remains isolated to the single source.
class OfficialAnkiFixturePilotSaga {
  const OfficialAnkiFixturePilotSaga({
    required this.dao,
    required this.coordinator,
    this.backupService = const LegacyAnkiBackupService(),
    this.dryRunSaga = const LegacyAnkiDryRunSaga(),
  });

  final OfficialAnkiMigrationDao dao;
  final OfficialAnkiOperationCoordinator coordinator;
  final LegacyAnkiBackupService backupService;
  final LegacyAnkiDryRunSaga dryRunSaga;

  void start({
    required String migrationId,
    required String profileId,
    required String legacyImportId,
    required LegacyAnkiSchedulingPolicy policy,
    String? sourceHash,
    String? displayName,
    int legacyCardCount = 0,
    int? nowMillis,
  }) {
    if (!isFixturePilotSource(
      importId: legacyImportId,
      sourceHash: sourceHash,
    )) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.non_allowlist_source',
        debugDetails: 'Source not in P5-C fixture allowlist',
      );
    }

    coordinator.requireNotReviewing();
    coordinator.acquire(OfficialAnkiOperationPhase.migrating);
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    try {
      final existing = dao.findByLegacyImport(
        profileId: profileId,
        legacyImportId: legacyImportId,
      );
      if (existing == null) {
        dao.insertDetected(
          migrationId: migrationId,
          profileId: profileId,
          legacyImportId: legacyImportId,
          policy: policy,
          sourceHash: sourceHash,
          legacyCardCount: legacyCardCount,
          nowMillis: now,
        );
        dao.transition(
          migrationId: migrationId,
          expected: LegacyAnkiMigrationState.detected,
          next: LegacyAnkiMigrationState.awaitingPackage,
          nowMillis: now,
        );
        return;
      }
      if (existing.state == LegacyAnkiMigrationState.detected) {
        dao.transition(
          migrationId: existing.migrationId,
          expected: LegacyAnkiMigrationState.detected,
          next: LegacyAnkiMigrationState.awaitingPackage,
          nowMillis: now,
        );
        return;
      }
      if (existing.state == LegacyAnkiMigrationState.needsUserAction) {
        dao.transition(
          migrationId: existing.migrationId,
          expected: LegacyAnkiMigrationState.needsUserAction,
          next: LegacyAnkiMigrationState.awaitingPackage,
          nowMillis: now,
        );
      }
    } catch (_) {
      coordinator.release(OfficialAnkiOperationPhase.migrating);
      rethrow;
    }
  }

  Future<bool> pickAndValidatePackage({
    required String migrationId,
    required File pickedFile,
    required String expectedSourceHash,
    required OfficialAnkiPaths paths,
    List<LegacyAnkiCardIdentity>? legacyCards,
    LegacyAnkiCensusReport? census,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    if (!pickedFile.existsSync()) {
      dao.transition(
        migrationId: migrationId,
        expected: LegacyAnkiMigrationState.awaitingPackage,
        next: LegacyAnkiMigrationState.needsUserAction,
        nowMillis: now,
        errorCode: 'official_anki.package_missing',
        errorMessage: 'Picked file does not exist',
      );
      return false;
    }

    final fileBytes = await pickedFile.readAsBytes();
    final computedHash = sha256.convert(fileBytes).toString();
    if (computedHash != expectedSourceHash) {
      dao.transition(
        migrationId: migrationId,
        expected: LegacyAnkiMigrationState.awaitingPackage,
        next: LegacyAnkiMigrationState.needsUserAction,
        nowMillis: now,
        errorCode: 'official_anki.migration_package_mismatch',
        errorMessage: 'Picked package sha256 does not match census sourceHash',
      );
      return false;
    }

    dao.transition(
      migrationId: migrationId,
      expected: LegacyAnkiMigrationState.awaitingPackage,
      next: LegacyAnkiMigrationState.validatingSource,
      nowMillis: now,
    );

    dao.transition(
      migrationId: migrationId,
      expected: LegacyAnkiMigrationState.validatingSource,
      next: LegacyAnkiMigrationState.backingUp,
      nowMillis: now,
    );

    final manifest = census != null
        ? backupService.generateFromCensus(
            census: census,
            officialBackupId: 'bak-$migrationId',
            createdAtMillis: now,
          )
        : backupService.generate(
            importCount: 1,
            noteCount: legacyCards?.map((c) => c.legacyNoteId).toSet().length ?? 0,
            cardCount: legacyCards?.length ?? 0,
            srsCount: legacyCards?.length ?? 0,
            officialBackupId: 'bak-$migrationId',
            createdAtMillis: now,
          );

    await backupService.createPhysicalBackup(
      paths: paths,
      migrationId: migrationId,
      manifest: manifest,
      legacyCards: legacyCards,
    );

    backupService.recordInDao(
      dao: dao,
      migrationId: migrationId,
      manifest: manifest,
      nowMillis: now,
    );

    return true;
  }

  Future<String> importOfficial({
    required String migrationId,
    required String packagePath,
    required OfficialAnkiImporter importer,
    String? displayName,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    dao.transition(
      migrationId: migrationId,
      expected: LegacyAnkiMigrationState.backingUp,
      next: LegacyAnkiMigrationState.importingOfficial,
      nowMillis: now,
    );

    final result = await importer.importFile(
      packagePath: packagePath,
      displayName: displayName ?? 'p5c-fixture-import',
    );

    dao.transition(
      migrationId: migrationId,
      expected: LegacyAnkiMigrationState.importingOfficial,
      next: LegacyAnkiMigrationState.indexingOfficial,
      nowMillis: now,
      officialSourceId: result.sourceId,
    );

    return result.sourceId;
  }

  Future<bool> indexAndMatchCards({
    required String migrationId,
    required List<LegacyAnkiCardIdentity> legacyCards,
    required List<OfficialAnkiCardIdentity> officialCards,
    bool sameTrustedPackage = false,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    dao.transition(
      migrationId: migrationId,
      expected: LegacyAnkiMigrationState.indexingOfficial,
      next: LegacyAnkiMigrationState.mappingCards,
      nowMillis: now,
    );

    dao.replaceDryRunMap(
      migrationId: migrationId,
      result: const LegacyAnkiDryRunResult(rows: []),
    );
    dao.setCursor(
      migrationId: migrationId,
      cursorLegacyCardId: 0,
      nowMillis: now,
    );

    final matchResult = await dryRunSaga.run(
      dao: dao,
      migrationId: migrationId,
      legacyCards: legacyCards,
      officialCards: officialCards,
      sameTrustedPackage: sameTrustedPackage,
      nowMillis: now,
    );

    final allMatched = matchResult.isFullyMatched &&
        matchResult.unresolvedCount == 0 &&
        matchResult.matchedCount == legacyCards.length;

    if (!allMatched) {
      dao.transition(
        migrationId: migrationId,
        expected: LegacyAnkiMigrationState.mappingCards,
        next: LegacyAnkiMigrationState.needsUserAction,
        nowMillis: now,
        matchedCardCount: matchResult.matchedCount,
        unresolvedCardCount: matchResult.unresolvedCount,
        errorCode: 'official_anki.mapping_unresolved',
        errorMessage: 'Card mapping has unresolved or collision rows',
      );
      return false;
    }

    dao.transition(
      migrationId: migrationId,
      expected: LegacyAnkiMigrationState.mappingCards,
      next: LegacyAnkiMigrationState.projectingCourse,
      nowMillis: now,
      matchedCardCount: matchResult.matchedCount,
      unresolvedCardCount: 0,
    );
    return true;
  }

  Future<bool> projectCourse({
    required String migrationId,
    Future<void> Function()? projectionAction,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    try {
      if (projectionAction != null) {
        await projectionAction();
      }
      dao.transition(
        migrationId: migrationId,
        expected: LegacyAnkiMigrationState.projectingCourse,
        next: LegacyAnkiMigrationState.verifying,
        nowMillis: now,
      );
      return true;
    } catch (e) {
      dao.transition(
        migrationId: migrationId,
        expected: LegacyAnkiMigrationState.projectingCourse,
        next: LegacyAnkiMigrationState.failedRecoverable,
        nowMillis: now,
        errorCode: 'official_anki.projection_failed',
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<bool> verifyAndCutover({
    required String migrationId,
    required int legacyCardCount,
    required int officialCardCount,
    int officialNoteCount = 0,
    int legacyNoteCount = 0,
    int officialDeckCount = 0,
    int legacyDeckCount = 0,
    int officialMediaCount = 0,
    int legacyMediaCount = 0,
    int projectionItemCount = 0,
    int matchedCount = 0,
    int officialMutationCountAtCutover = 0,
    Future<void> Function()? onCutover,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final mismatches = <String>[];
    if (officialCardCount < legacyCardCount) {
      mismatches.add('cards official=$officialCardCount < legacy=$legacyCardCount');
    }
    if (matchedCount != legacyCardCount) {
      mismatches.add('matched $matchedCount!=$legacyCardCount');
    }
    if (matchedCount > 0 && projectionItemCount == 0) {
      mismatches.add('projection 0!=matched $matchedCount');
    }
    if (legacyNoteCount != officialNoteCount) {
      mismatches.add('notes $legacyNoteCount!=$officialNoteCount');
    }
    if (legacyDeckCount != officialDeckCount) {
      mismatches.add('decks $legacyDeckCount!=$officialDeckCount');
    }
    if (legacyMediaCount != officialMediaCount) {
      mismatches.add('media $legacyMediaCount!=$officialMediaCount');
    }
    if (projectionItemCount != 0 &&
        projectionItemCount != matchedCount &&
        projectionItemCount != officialCardCount) {
      mismatches.add(
        'projection $projectionItemCount!=matched $matchedCount/official $officialCardCount',
      );
    }
    if (mismatches.isNotEmpty) {
      dao.transition(
        migrationId: migrationId,
        expected: LegacyAnkiMigrationState.verifying,
        next: LegacyAnkiMigrationState.needsUserAction,
        nowMillis: now,
        errorCode: 'official_anki.verify_count_mismatch',
        errorMessage: mismatches.join('; '),
      );
      return false;
    }

    dao.transition(
      migrationId: migrationId,
      expected: LegacyAnkiMigrationState.verifying,
      next: LegacyAnkiMigrationState.cutoverReady,
      nowMillis: now,
    );

    dao.setOfficialMutationCountAtCutover(
      migrationId: migrationId,
      count: officialMutationCountAtCutover,
      nowMillis: now,
    );

    dao.setRecordedKind(
      migrationId: migrationId,
      recordedKind: 'official',
      nowMillis: now,
    );

    dao.transition(
      migrationId: migrationId,
      expected: LegacyAnkiMigrationState.cutoverReady,
      next: LegacyAnkiMigrationState.cutover,
      nowMillis: now,
    );

    if (onCutover != null) {
      await onCutover();
    }

    dao.transition(
      migrationId: migrationId,
      expected: LegacyAnkiMigrationState.cutover,
      next: LegacyAnkiMigrationState.observing,
      nowMillis: now,
    );

    return true;
  }

  void rollback({
    required String migrationId,
    required LegacyAnkiMigrationState currentState,
    int? officialMutationDelta,
    int? nowMillis,
  }) {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final storedRow = dao.findById(migrationId);
    final stored = storedRow?.officialMutationCountAtCutover ?? 0;
    final delta = officialMutationDelta ?? stored;
    if (currentState == LegacyAnkiMigrationState.cutover ||
        currentState == LegacyAnkiMigrationState.observing) {
      if (delta == 0) {
        dao.setRecordedKind(
          migrationId: migrationId,
          recordedKind: 'legacy',
          nowMillis: now,
        );
        dao.transition(
          migrationId: migrationId,
          expected: currentState,
          next: LegacyAnkiMigrationState.rollbackEligible,
          nowMillis: now,
        );
      } else {
        dao.transition(
          migrationId: migrationId,
          expected: currentState,
          next: LegacyAnkiMigrationState.noLegacyScheduleRollback,
          nowMillis: now,
        );
      }
    } else {
      dao.transition(
        migrationId: migrationId,
        expected: currentState,
        next: LegacyAnkiMigrationState.rolledBackLegacy,
        nowMillis: now,
      );
    }
  }

  void releaseLease() {
    coordinator.release(OfficialAnkiOperationPhase.migrating);
  }
}
