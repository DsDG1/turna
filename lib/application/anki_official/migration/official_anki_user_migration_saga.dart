import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart';
import 'package:turna/application/anki_official/migration/official_anki_backup_manifest.dart';
import 'package:turna/application/anki_official/migration/official_anki_census.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_saga.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_user_allowlist.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

class OfficialAnkiUserMigrationSaga {
  const OfficialAnkiUserMigrationSaga({
    required this.dao,
    required this.coordinator,
    this.backupService = const LegacyAnkiBackupService(),
    this.dryRunSaga = const LegacyAnkiDryRunSaga(),
  });

  final OfficialAnkiMigrationDao dao;
  final OfficialAnkiOperationCoordinator coordinator;
  final LegacyAnkiBackupService backupService;
  final LegacyAnkiDryRunSaga dryRunSaga;

  void _requireAllowlisted({
    required String importId,
    required String sourceHash,
  }) {
    if (!isUserAllowlistedSource(importId: importId, sourceHash: sourceHash)) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.non_allowlist_source',
        debugDetails: 'User source not in written allowlist',
      );
    }
  }

  void start({
    required String migrationId,
    required String profileId,
    required String legacyImportId,
    required String sourceHash,
    required LegacyAnkiSchedulingPolicy policy,
    int legacyCardCount = 0,
    int? nowMillis,
  }) {
    _requireAllowlisted(importId: legacyImportId, sourceHash: sourceHash);
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
    required String importId,
    List<LegacyAnkiCardIdentity>? legacyCards,
    LegacyAnkiCensusReport? census,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    _requireAllowlisted(importId: importId, sourceHash: expectedSourceHash);
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
    final computed = sha256.convert(await pickedFile.readAsBytes()).toString();
    if (computed != expectedSourceHash) {
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

  void releaseLease() {
    coordinator.release(OfficialAnkiOperationPhase.migrating);
  }
}
