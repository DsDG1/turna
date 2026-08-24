import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_source_reconciler.dart';
import 'package:turna/application/anki_official/migration/official_legacy_source_migration_saga.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';

/// Production entry for W8: census `cleanLegacy` rows become one-at-a-time
/// saga jobs. Does not import packages or switch owner by itself — callers
/// must confirm [LegacyAnkiSchedulingPolicy] first (doc 34 §12.3).
class OfficialLegacyMigrationDriver {
  const OfficialLegacyMigrationDriver();

  List<OfficialAnkiSourceCensusRow> pendingCleanLegacy(
    OfficialAnkiSourceCensusReport report,
  ) {
    return [
      for (final row in report.rows)
        if (row.decision.state == OfficialAnkiSourceReconcileState.cleanLegacy)
          row,
    ];
  }

  /// Enqueue a single cleanLegacy source. Throws if the census state is not
  /// cleanLegacy or the import id / hash is missing.
  void beginOne({
    required OfficialLegacySourceMigrationSaga saga,
    required OfficialAnkiSourceCensusRow row,
    required LegacyAnkiSchedulingPolicy policy,
    required bool policyConfirmedByUser,
    String? migrationId,
    int? nowMillis,
  }) {
    if (row.decision.state != OfficialAnkiSourceReconcileState.cleanLegacy) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.migration_not_clean_legacy',
        debugDetails: row.decision.state.name,
      );
    }
    final importId = row.evidence.importId ?? '';
    final hash = row.evidence.sourceHash ?? '';
    if (importId.isEmpty || hash.isEmpty) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.migration_missing_legacy_identity',
      );
    }
    saga.beginFromCleanLegacyCensus(
      migrationId: migrationId ?? newOfficialAnkiId('mig'),
      profileId: row.evidence.profileId,
      legacyImportId: importId,
      sourceHash: hash,
      policy: policy,
      policyConfirmedByUser: policyConfirmedByUser,
      censusStatus: kCleanLegacyCensusStatus,
      legacyCardCount: row.evidence.legacyCardCount,
      nowMillis: nowMillis,
    );
  }

  /// Resume a crashed / interrupted saga from its journal state. The saga
  /// derives the next action itself (plan 34 §R4-3: every step
  /// crash/resumable).
  OfficialLegacyMigrationResumeAction resumeOne({
    required OfficialLegacySourceMigrationSaga saga,
    required String migrationId,
  }) {
    return saga.resume(migrationId: migrationId);
  }

  /// Roll back BEFORE the owner commit: restores the Legacy writer through
  /// the journal (post-commit attempts are refused by the saga; they take
  /// the forward-recovery path instead — plan 34 §R4-3).
  void rollbackOne({
    required OfficialLegacySourceMigrationSaga saga,
    required String migrationId,
    int? officialMutationDelta,
    int? nowMillis,
  }) {
    final row = saga.dao.findById(migrationId);
    if (row == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.migration_missing',
      );
    }
    saga.rollback(
      migrationId: migrationId,
      currentState: row.state,
      officialMutationDelta: officialMutationDelta,
      nowMillis: nowMillis,
    );
  }
}
