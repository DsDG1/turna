import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

/// Doc 34 W3 — source census, reconciler, and reconciliation journal.
///
/// Owner decisions use **persisted evidence only**. Build / feature flags must
/// never invent or override historical owner (doc 34 §0.1 / §7.1).

/// Standard source states from doc 34 §7.2.
enum OfficialAnkiSourceReconcileState {
  cleanOfficial,
  cleanLegacy,
  mirroredConsistent,
  ownerOfficialCollectionMissing,
  ownerOfficialProjectionMissing,
  ownerLegacySrsMissing,
  ownerMismatch,
  pendingCleanup,
  legacyPendingMigration,
  unknownQuarantined,
}

/// Persisted owner as recorded on migration / unification rows — not flags.
enum OfficialAnkiPersistedOwner {
  official,
  legacy,
}

/// Automatic action suggested by the reconciler (never applied by census).
enum OfficialAnkiReconcileAutoAction {
  useNormally,
  queueMigration,
  freezeAndChooseOwner,
  failClosedRepairFromBackup,
  rebuildProjection,
  quarantineNoFakeMigration,
  isolateAndPlanRepair,
  retryCleanup,
  readOnlyAwaitW8,
  diagnoseExportOnly,
}

/// Read-only evidence snapshot for one source candidate.
///
/// Fields are counts / ids / fingerprints only — never card text or media.
class OfficialAnkiSourceEvidence {
  const OfficialAnkiSourceEvidence({
    required this.profileId,
    this.sourceId,
    this.importId,
    this.sourceHash,
    this.recordedOwner,
    this.unificationBackend,
    this.migrationRecordedKind,
    this.migrationOfficialSourceId,
    this.migrationState,
    this.officialSourceState,
    this.officialCardCount = 0,
    this.collectionPresent = false,
    this.projectionPresent = false,
    this.placementCount = 0,
    this.identityRowCount = 0,
    this.legacyImportPresent = false,
    this.legacyNoteCount = 0,
    this.legacyCardCount = 0,
    this.legacySrsCount = 0,
    this.cardinalityConflict = false,
    this.identityConsistent = true,
    this.fromLegacyPendingPath = false,
  });

  final String profileId;
  final String? sourceId;
  final String? importId;
  final String? sourceHash;

  /// Explicit persisted owner when one authoritative row exists.
  final OfficialAnkiPersistedOwner? recordedOwner;

  /// `anki_course_sources.backend_kind` (`official` / `legacyTurna` / …).
  final String? unificationBackend;

  /// `legacy_anki_migrations.recorded_kind`.
  final String? migrationRecordedKind;
  final String? migrationOfficialSourceId;
  final String? migrationState;

  /// Catalog `anki_sources.state` (`active`, `pending_cleanup`, …).
  final String? officialSourceState;
  final int officialCardCount;
  final bool collectionPresent;

  final bool projectionPresent;
  final int placementCount;
  final int identityRowCount;

  final bool legacyImportPresent;
  final int legacyNoteCount;
  final int legacyCardCount;
  final int legacySrsCount;

  /// True when mirrored card/note counts cannot be reconciled.
  final bool cardinalityConflict;

  /// True when mirrored identity keys line up (guid/ord or card map).
  final bool identityConsistent;

  /// Marked as coming from pre-cutover Android/OHOS legacy import path.
  final bool fromLegacyPendingPath;

  bool get hasOfficialCatalogSource =>
      sourceId != null &&
      sourceId!.isNotEmpty &&
      officialSourceState != null &&
      officialSourceState != 'deleted';

  bool get officialActive =>
      hasOfficialCatalogSource && officialSourceState == 'active';

  bool get officialPendingCleanup => officialSourceState == 'pending_cleanup';

  bool get hasOfficialCards => collectionPresent && officialCardCount > 0;

  bool get projectionComplete =>
      projectionPresent &&
      (placementCount > 0 || identityRowCount > 0) &&
      (!hasOfficialCards ||
          placementCount >= officialCardCount ||
          identityRowCount >= officialCardCount);

  bool get hasLegacyNotes =>
      legacyImportPresent && (legacyNoteCount > 0 || legacyCardCount > 0);

  bool get legacySrsComplete =>
      hasLegacyNotes && legacySrsCount > 0 && legacySrsCount >= legacyCardCount;

  /// Stable hash over evidence fields (no privacy payload).
  String evidenceHash() {
    final payload = <String, Object?>{
      'profileId': profileId,
      'sourceId': sourceId,
      'importId': importId,
      'sourceHash': sourceHash,
      'recordedOwner': recordedOwner?.name,
      'unificationBackend': unificationBackend,
      'migrationRecordedKind': migrationRecordedKind,
      'migrationOfficialSourceId': migrationOfficialSourceId,
      'migrationState': migrationState,
      'officialSourceState': officialSourceState,
      'officialCardCount': officialCardCount,
      'collectionPresent': collectionPresent,
      'projectionPresent': projectionPresent,
      'placementCount': placementCount,
      'identityRowCount': identityRowCount,
      'legacyImportPresent': legacyImportPresent,
      'legacyNoteCount': legacyNoteCount,
      'legacyCardCount': legacyCardCount,
      'legacySrsCount': legacySrsCount,
      'cardinalityConflict': cardinalityConflict,
      'identityConsistent': identityConsistent,
      'fromLegacyPendingPath': fromLegacyPendingPath,
    };
    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }
}

class OfficialAnkiSourceReconcileDecision {
  const OfficialAnkiSourceReconcileDecision({
    required this.state,
    required this.autoAction,
    required this.evidenceHash,
    this.intendedOwner,
    this.reasons = const <String>[],
    this.repairPlan,
  });

  final OfficialAnkiSourceReconcileState state;
  final OfficialAnkiReconcileAutoAction autoAction;
  final String evidenceHash;

  /// Set only when evidence already agrees on one owner. Never invented by
  /// comparing which side has more cards.
  final OfficialAnkiPersistedOwner? intendedOwner;
  final List<String> reasons;
  final OfficialAnkiProjectionRebuildPlan? repairPlan;
}

/// Projection-only rebuild plan. Must not touch scheduler or revlog.
class OfficialAnkiProjectionRebuildPlan {
  const OfficialAnkiProjectionRebuildPlan({
    required this.sourceId,
    required this.profileId,
    required this.expectedOfficialCardCount,
  });

  final String sourceId;
  final String profileId;
  final int expectedOfficialCardCount;

  /// Contract: rebuild writes projection/placement/identity only.
  bool get mutatesScheduler => false;
  bool get mutatesRevlog => false;
  bool get mutatesCollectionCards => false;
}

/// Doc 34 §7.1–7.2: classify one source from persisted evidence only.
class OfficialAnkiSourceReconciler {
  const OfficialAnkiSourceReconciler();

  OfficialAnkiSourceReconcileDecision classify(
    OfficialAnkiSourceEvidence evidence,
  ) {
    final hash = evidence.evidenceHash();
    final mismatch = _ownerMismatch(evidence);
    if (mismatch != null) {
      return OfficialAnkiSourceReconcileDecision(
        state: OfficialAnkiSourceReconcileState.ownerMismatch,
        autoAction: OfficialAnkiReconcileAutoAction.isolateAndPlanRepair,
        evidenceHash: hash,
        // Explicitly null — never auto-pick the "larger" side.
        intendedOwner: null,
        reasons: mismatch,
      );
    }

    if (evidence.officialPendingCleanup) {
      return OfficialAnkiSourceReconcileDecision(
        state: OfficialAnkiSourceReconcileState.pendingCleanup,
        autoAction: OfficialAnkiReconcileAutoAction.retryCleanup,
        evidenceHash: hash,
        intendedOwner: OfficialAnkiPersistedOwner.official,
        reasons: const ['official_source_pending_cleanup'],
      );
    }

    if (evidence.cardinalityConflict || !evidence.identityConsistent) {
      return OfficialAnkiSourceReconcileDecision(
        state: OfficialAnkiSourceReconcileState.unknownQuarantined,
        autoAction: OfficialAnkiReconcileAutoAction.diagnoseExportOnly,
        evidenceHash: hash,
        intendedOwner: null,
        reasons: [
          if (evidence.cardinalityConflict) 'cardinality_conflict',
          if (!evidence.identityConsistent) 'identity_inconsistent',
        ],
      );
    }

    final owner = _resolvedPersistedOwner(evidence);

    if (owner == OfficialAnkiPersistedOwner.official) {
      if (!evidence.hasOfficialCards) {
        return OfficialAnkiSourceReconcileDecision(
          state:
              OfficialAnkiSourceReconcileState.ownerOfficialCollectionMissing,
          autoAction:
              OfficialAnkiReconcileAutoAction.failClosedRepairFromBackup,
          evidenceHash: hash,
          intendedOwner: OfficialAnkiPersistedOwner.official,
          reasons: const ['owner_official_but_collection_missing'],
        );
      }
      if (!evidence.projectionComplete) {
        final sourceId = evidence.sourceId ?? '';
        return OfficialAnkiSourceReconcileDecision(
          state:
              OfficialAnkiSourceReconcileState.ownerOfficialProjectionMissing,
          autoAction: OfficialAnkiReconcileAutoAction.rebuildProjection,
          evidenceHash: hash,
          intendedOwner: OfficialAnkiPersistedOwner.official,
          reasons: const ['projection_or_placement_missing'],
          repairPlan: sourceId.isEmpty
              ? null
              : OfficialAnkiProjectionRebuildPlan(
                  sourceId: sourceId,
                  profileId: evidence.profileId,
                  expectedOfficialCardCount: evidence.officialCardCount,
                ),
        );
      }
      if (evidence.legacySrsCount > 0 && !evidence.hasLegacyNotes) {
        return OfficialAnkiSourceReconcileDecision(
          state: OfficialAnkiSourceReconcileState.unknownQuarantined,
          autoAction: OfficialAnkiReconcileAutoAction.diagnoseExportOnly,
          evidenceHash: hash,
          intendedOwner: OfficialAnkiPersistedOwner.official,
          reasons: const ['official_owner_with_orphan_turna_srs'],
        );
      }
      if (evidence.hasLegacyNotes && evidence.hasOfficialCards) {
        return OfficialAnkiSourceReconcileDecision(
          state: OfficialAnkiSourceReconcileState.mirroredConsistent,
          autoAction: OfficialAnkiReconcileAutoAction.freezeAndChooseOwner,
          evidenceHash: hash,
          intendedOwner: OfficialAnkiPersistedOwner.official,
          reasons: const ['both_sides_present_identity_ok'],
        );
      }
      if (evidence.legacySrsCount > 0) {
        return OfficialAnkiSourceReconcileDecision(
          state: OfficialAnkiSourceReconcileState.mirroredConsistent,
          autoAction: OfficialAnkiReconcileAutoAction.freezeAndChooseOwner,
          evidenceHash: hash,
          intendedOwner: OfficialAnkiPersistedOwner.official,
          reasons: const ['official_complete_but_turna_srs_present'],
        );
      }
      return OfficialAnkiSourceReconcileDecision(
        state: OfficialAnkiSourceReconcileState.cleanOfficial,
        autoAction: OfficialAnkiReconcileAutoAction.useNormally,
        evidenceHash: hash,
        intendedOwner: OfficialAnkiPersistedOwner.official,
        reasons: const ['catalog_active_projection_complete_no_turna_srs'],
      );
    }

    if (owner == OfficialAnkiPersistedOwner.legacy) {
      if (evidence.hasLegacyNotes && evidence.legacySrsCount == 0) {
        return OfficialAnkiSourceReconcileDecision(
          state: OfficialAnkiSourceReconcileState.ownerLegacySrsMissing,
          autoAction:
              OfficialAnkiReconcileAutoAction.quarantineNoFakeMigration,
          evidenceHash: hash,
          intendedOwner: OfficialAnkiPersistedOwner.legacy,
          reasons: const ['legacy_notes_without_srs'],
        );
      }
      if (evidence.officialActive && evidence.hasOfficialCards) {
        return OfficialAnkiSourceReconcileDecision(
          state: OfficialAnkiSourceReconcileState.mirroredConsistent,
          autoAction: OfficialAnkiReconcileAutoAction.freezeAndChooseOwner,
          evidenceHash: hash,
          intendedOwner: OfficialAnkiPersistedOwner.legacy,
          reasons: const ['legacy_owner_with_official_mirror'],
        );
      }
      if (evidence.fromLegacyPendingPath ||
          _isMigrationPending(evidence.migrationState)) {
        return OfficialAnkiSourceReconcileDecision(
          state: OfficialAnkiSourceReconcileState.legacyPendingMigration,
          autoAction: OfficialAnkiReconcileAutoAction.readOnlyAwaitW8,
          evidenceHash: hash,
          intendedOwner: OfficialAnkiPersistedOwner.legacy,
          reasons: const ['legacy_path_awaiting_w8'],
        );
      }
      if (evidence.hasLegacyNotes && evidence.legacySrsComplete) {
        return OfficialAnkiSourceReconcileDecision(
          state: OfficialAnkiSourceReconcileState.cleanLegacy,
          autoAction: OfficialAnkiReconcileAutoAction.queueMigration,
          evidenceHash: hash,
          intendedOwner: OfficialAnkiPersistedOwner.legacy,
          reasons: const ['legacy_complete_no_official_active'],
        );
      }
      return OfficialAnkiSourceReconcileDecision(
        state: OfficialAnkiSourceReconcileState.unknownQuarantined,
        autoAction: OfficialAnkiReconcileAutoAction.diagnoseExportOnly,
        evidenceHash: hash,
        intendedOwner: OfficialAnkiPersistedOwner.legacy,
        reasons: const ['legacy_owner_incomplete_evidence'],
      );
    }

    // No authoritative persisted owner — never invent one from flags/surfaces.
    if (evidence.hasLegacyNotes && evidence.legacySrsCount == 0) {
      return OfficialAnkiSourceReconcileDecision(
        state: OfficialAnkiSourceReconcileState.ownerLegacySrsMissing,
        autoAction: OfficialAnkiReconcileAutoAction.quarantineNoFakeMigration,
        evidenceHash: hash,
        intendedOwner: null,
        reasons: const ['notes_without_owner_or_srs'],
      );
    }
    if (evidence.fromLegacyPendingPath && evidence.hasLegacyNotes) {
      return OfficialAnkiSourceReconcileDecision(
        state: OfficialAnkiSourceReconcileState.legacyPendingMigration,
        autoAction: OfficialAnkiReconcileAutoAction.readOnlyAwaitW8,
        evidenceHash: hash,
        intendedOwner: null,
        reasons: const ['unmarked_legacy_pending_path'],
      );
    }
    if (evidence.officialActive &&
        evidence.hasOfficialCards &&
        evidence.projectionComplete &&
        evidence.legacySrsCount == 0 &&
        !evidence.hasLegacyNotes) {
      return OfficialAnkiSourceReconcileDecision(
        state: OfficialAnkiSourceReconcileState.unknownQuarantined,
        autoAction: OfficialAnkiReconcileAutoAction.diagnoseExportOnly,
        evidenceHash: hash,
        intendedOwner: null,
        reasons: const ['complete_surfaces_but_no_persisted_owner'],
      );
    }

    return OfficialAnkiSourceReconcileDecision(
      state: OfficialAnkiSourceReconcileState.unknownQuarantined,
      autoAction: OfficialAnkiReconcileAutoAction.diagnoseExportOnly,
      evidenceHash: hash,
      intendedOwner: null,
      reasons: const ['insufficient_persisted_evidence'],
    );
  }

  OfficialAnkiPersistedOwner? _resolvedPersistedOwner(
    OfficialAnkiSourceEvidence evidence,
  ) {
    if (evidence.recordedOwner != null) return evidence.recordedOwner;
    final fromMigration = parseRecordedKind(evidence.migrationRecordedKind);
    if (fromMigration == AnkiEngineKind.official) {
      return OfficialAnkiPersistedOwner.official;
    }
    if (fromMigration == AnkiEngineKind.legacy) {
      return OfficialAnkiPersistedOwner.legacy;
    }
    final backend = evidence.unificationBackend;
    if (backend == 'official') return OfficialAnkiPersistedOwner.official;
    if (backend == 'legacyTurna' || backend == 'legacy') {
      return OfficialAnkiPersistedOwner.legacy;
    }
    return null;
  }

  List<String>? _ownerMismatch(OfficialAnkiSourceEvidence evidence) {
    final claims = <OfficialAnkiPersistedOwner>{};

    if (evidence.recordedOwner != null) {
      claims.add(evidence.recordedOwner!);
    }
    final mig = parseRecordedKind(evidence.migrationRecordedKind);
    if (mig == AnkiEngineKind.official) {
      claims.add(OfficialAnkiPersistedOwner.official);
    } else if (mig == AnkiEngineKind.legacy) {
      claims.add(OfficialAnkiPersistedOwner.legacy);
    }
    final backend = evidence.unificationBackend;
    if (backend == 'official') {
      claims.add(OfficialAnkiPersistedOwner.official);
    } else if (backend == 'legacyTurna' || backend == 'legacy') {
      claims.add(OfficialAnkiPersistedOwner.legacy);
    }

    if (claims.length > 1) {
      return [
        'persisted_owner_claims_disagree',
        'claims=${claims.map((c) => c.name).toList()..sort()}',
      ];
    }

    if (claims.contains(OfficialAnkiPersistedOwner.official) &&
        evidence.sourceId != null &&
        evidence.migrationOfficialSourceId != null &&
        evidence.migrationOfficialSourceId!.isNotEmpty &&
        evidence.migrationOfficialSourceId != evidence.sourceId) {
      return [
        'migration_official_source_id_mismatch',
        'catalog=${evidence.sourceId}',
        'migration=${evidence.migrationOfficialSourceId}',
      ];
    }

    return null;
  }

  bool _isMigrationPending(String? state) {
    if (state == null) return false;
    const pending = {
      'detected',
      'awaitingPackage',
      'validatingSource',
      'backingUp',
      'importingOfficial',
      'indexingOfficial',
      'mappingCards',
      'projectingCourse',
      'verifying',
      'cutoverReady',
      'needsUserAction',
      'failedRecoverable',
    };
    return pending.contains(state);
  }
}

// ---------------------------------------------------------------------------
// Reconciliation journal (doc 34 §7.3)
// ---------------------------------------------------------------------------

enum OfficialAnkiReconcileRetryPolicy {
  resumeFromStep,
  restartFromBackup,
  manualOnly,
}

enum OfficialAnkiReconcileRollbackPolicy {
  restoreBackup,
  leaveQuarantined,
  none,
}

/// Journal steps for a single-source repair. Mid-kill leaves the row so the
/// next boot can resume or quarantine (doc 34 §7.5).
enum OfficialAnkiReconcileJournalStep {
  scanned,
  planned,
  backedUp,
  mutating,
  verifying,
  completed,
  failed,
  quarantined,
}

class OfficialAnkiReconciliationJournalEntry {
  const OfficialAnkiReconciliationJournalEntry({
    required this.operationId,
    required this.profileId,
    required this.beforeState,
    required this.evidenceHash,
    required this.currentStep,
    required this.retryPolicy,
    required this.rollbackPolicy,
    required this.updatedAtMillis,
    this.sourceId,
    this.importId,
    this.intendedOwner,
    this.backupId,
    this.completedMutations = const <String>[],
    this.lastError,
    this.afterCardinality,
    this.afterFingerprint,
    this.createdAtMillis,
  });

  final String operationId;
  final String profileId;
  final String? sourceId;
  final String? importId;
  final OfficialAnkiSourceReconcileState beforeState;
  final String evidenceHash;
  final OfficialAnkiPersistedOwner? intendedOwner;
  final String? backupId;
  final OfficialAnkiReconcileJournalStep currentStep;
  final List<String> completedMutations;
  final String? lastError;
  final OfficialAnkiReconcileRetryPolicy retryPolicy;
  final OfficialAnkiReconcileRollbackPolicy rollbackPolicy;
  final int? afterCardinality;
  final String? afterFingerprint;
  final int? createdAtMillis;
  final int updatedAtMillis;

  bool get isTerminal =>
      currentStep == OfficialAnkiReconcileJournalStep.completed ||
      currentStep == OfficialAnkiReconcileJournalStep.quarantined;

  bool get isResumable =>
      !isTerminal && currentStep != OfficialAnkiReconcileJournalStep.failed;

  Map<String, Object?> toJson() => <String, Object?>{
        'operationId': operationId,
        'profileId': profileId,
        'sourceId': sourceId,
        'importId': importId,
        'beforeState': beforeState.name,
        'evidenceHash': evidenceHash,
        'intendedOwner': intendedOwner?.name,
        'backupId': backupId,
        'currentStep': currentStep.name,
        'completedMutations': completedMutations,
        'lastError': lastError,
        'retryPolicy': retryPolicy.name,
        'rollbackPolicy': rollbackPolicy.name,
        'afterCardinality': afterCardinality,
        'afterFingerprint': afterFingerprint,
        'createdAtMillis': createdAtMillis,
        'updatedAtMillis': updatedAtMillis,
      };
}

class OfficialAnkiReconciliationJournalDao {
  OfficialAnkiReconciliationJournalDao(this._database);

  final OfficialAnkiDatabase _database;
  Database get _db => _database.handle;

  void insert(OfficialAnkiReconciliationJournalEntry entry) {
    _db.execute(
      '''
INSERT INTO anki_source_reconciliation_journal (
  operation_id, profile_id, source_id, import_id, before_state, evidence_hash,
  intended_owner, backup_id, current_step, completed_mutations_json, last_error,
  retry_policy, rollback_policy, after_cardinality, after_fingerprint,
  created_at_millis, updated_at_millis
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        entry.operationId,
        entry.profileId,
        entry.sourceId,
        entry.importId,
        entry.beforeState.name,
        entry.evidenceHash,
        entry.intendedOwner?.name,
        entry.backupId,
        entry.currentStep.name,
        jsonEncode(entry.completedMutations),
        entry.lastError,
        entry.retryPolicy.name,
        entry.rollbackPolicy.name,
        entry.afterCardinality,
        entry.afterFingerprint,
        entry.createdAtMillis ?? entry.updatedAtMillis,
        entry.updatedAtMillis,
      ],
    );
  }

  OfficialAnkiReconciliationJournalEntry? findByEvidenceHash({
    required String profileId,
    required String evidenceHash,
  }) {
    final rows = _db.select(
      '''
SELECT * FROM anki_source_reconciliation_journal
WHERE profile_id = ? AND evidence_hash = ?
ORDER BY updated_at_millis DESC LIMIT 1
''',
      [profileId, evidenceHash],
    );
    if (rows.isEmpty) return null;
    return _row(rows.first);
  }

  OfficialAnkiReconciliationJournalEntry? findById(String operationId) {
    final rows = _db.select(
      'SELECT * FROM anki_source_reconciliation_journal WHERE operation_id = ?',
      [operationId],
    );
    if (rows.isEmpty) return null;
    return _row(rows.first);
  }

  List<OfficialAnkiReconciliationJournalEntry> listOpen({
    required String profileId,
  }) {
    return _db
        .select(
          '''
SELECT * FROM anki_source_reconciliation_journal
WHERE profile_id = ?
  AND current_step NOT IN ('completed', 'quarantined')
ORDER BY updated_at_millis DESC
''',
          [profileId],
        )
        .map(_row)
        .toList();
  }

  /// Advance journal step. Completed mutations are append-only.
  void advance({
    required String operationId,
    required OfficialAnkiReconcileJournalStep from,
    required OfficialAnkiReconcileJournalStep to,
    required int nowMillis,
    String? backupId,
    String? mutation,
    String? lastError,
    int? afterCardinality,
    String? afterFingerprint,
    OfficialAnkiPersistedOwner? intendedOwner,
  }) {
    final current = findById(operationId);
    if (current == null) {
      throw StateError('journal $operationId missing');
    }
    if (current.currentStep != from) {
      throw StateError(
        'journal $operationId expected ${from.name} was ${current.currentStep.name}',
      );
    }
    final mutations = [...current.completedMutations];
    if (mutation != null && mutation.isNotEmpty) {
      mutations.add(mutation);
    }
    _db.execute(
      '''
UPDATE anki_source_reconciliation_journal
SET current_step = ?, updated_at_millis = ?,
    backup_id = COALESCE(?, backup_id),
    completed_mutations_json = ?,
    last_error = ?,
    after_cardinality = COALESCE(?, after_cardinality),
    after_fingerprint = COALESCE(?, after_fingerprint),
    intended_owner = COALESCE(?, intended_owner)
WHERE operation_id = ? AND current_step = ?
''',
      [
        to.name,
        nowMillis,
        backupId,
        jsonEncode(mutations),
        lastError,
        afterCardinality,
        afterFingerprint,
        intendedOwner?.name,
        operationId,
        from.name,
      ],
    );
    if (_db.updatedRows != 1) {
      throw StateError('journal CAS failed for $operationId');
    }
  }

  /// Kill mid-step recovery: open journals become quarantined + resumable
  /// via retry policy.
  void quarantineOpenOperation({
    required String operationId,
    required int nowMillis,
    String lastError = 'interrupted_mid_step',
  }) {
    final current = findById(operationId);
    if (current == null || current.isTerminal) return;
    _db.execute(
      '''
UPDATE anki_source_reconciliation_journal
SET current_step = ?, last_error = ?, updated_at_millis = ?,
    retry_policy = ?
WHERE operation_id = ?
''',
      [
        OfficialAnkiReconcileJournalStep.quarantined.name,
        lastError,
        nowMillis,
        OfficialAnkiReconcileRetryPolicy.resumeFromStep.name,
        operationId,
      ],
    );
  }

  OfficialAnkiReconciliationJournalEntry _row(Row row) {
    final rawMutations = row['completed_mutations_json'] as String? ?? '[]';
    final decoded = jsonDecode(rawMutations);
    final mutations = decoded is List
        ? decoded.map((e) => e.toString()).toList()
        : const <String>[];
    return OfficialAnkiReconciliationJournalEntry(
      operationId: row['operation_id'] as String,
      profileId: row['profile_id'] as String,
      sourceId: row['source_id'] as String?,
      importId: row['import_id'] as String?,
      beforeState: OfficialAnkiSourceReconcileState.values.firstWhere(
        (s) => s.name == row['before_state'],
        orElse: () => OfficialAnkiSourceReconcileState.unknownQuarantined,
      ),
      evidenceHash: row['evidence_hash'] as String,
      intendedOwner: _parseOwner(row['intended_owner'] as String?),
      backupId: row['backup_id'] as String?,
      currentStep: OfficialAnkiReconcileJournalStep.values.firstWhere(
        (s) => s.name == row['current_step'],
        orElse: () => OfficialAnkiReconcileJournalStep.failed,
      ),
      completedMutations: mutations,
      lastError: row['last_error'] as String?,
      retryPolicy: OfficialAnkiReconcileRetryPolicy.values.firstWhere(
        (s) => s.name == row['retry_policy'],
        orElse: () => OfficialAnkiReconcileRetryPolicy.manualOnly,
      ),
      rollbackPolicy: OfficialAnkiReconcileRollbackPolicy.values.firstWhere(
        (s) => s.name == row['rollback_policy'],
        orElse: () => OfficialAnkiReconcileRollbackPolicy.leaveQuarantined,
      ),
      afterCardinality: (row['after_cardinality'] as num?)?.toInt(),
      afterFingerprint: row['after_fingerprint'] as String?,
      createdAtMillis: (row['created_at_millis'] as num?)?.toInt(),
      updatedAtMillis: (row['updated_at_millis'] as num).toInt(),
    );
  }

  OfficialAnkiPersistedOwner? _parseOwner(String? raw) {
    if (raw == 'official') return OfficialAnkiPersistedOwner.official;
    if (raw == 'legacy') return OfficialAnkiPersistedOwner.legacy;
    return null;
  }
}

// ---------------------------------------------------------------------------
// Read-only census (doc 34 §7.4 steps 1–4)
// ---------------------------------------------------------------------------

class OfficialAnkiSourceCensusRow {
  const OfficialAnkiSourceCensusRow({
    required this.evidence,
    required this.decision,
  });

  final OfficialAnkiSourceEvidence evidence;
  final OfficialAnkiSourceReconcileDecision decision;

  Map<String, Object?> toJson() => <String, Object?>{
        'profileId': evidence.profileId,
        'sourceId': evidence.sourceId,
        'importId': evidence.importId,
        'sourceHash': evidence.sourceHash,
        'state': decision.state.name,
        'autoAction': decision.autoAction.name,
        'evidenceHash': decision.evidenceHash,
        'intendedOwner': decision.intendedOwner?.name,
        'reasons': decision.reasons,
        'officialCardCount': evidence.officialCardCount,
        'legacyCardCount': evidence.legacyCardCount,
        'legacySrsCount': evidence.legacySrsCount,
      };
}

class OfficialAnkiSourceCensusReport {
  const OfficialAnkiSourceCensusReport({
    required this.generatedAtMillis,
    required this.rows,
  });

  static const schemaVersion = 1;

  final int generatedAtMillis;
  final List<OfficialAnkiSourceCensusRow> rows;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'generatedAtMillis': generatedAtMillis,
        'sourceCount': rows.length,
        'byState': <String, int>{
          for (final state in OfficialAnkiSourceReconcileState.values)
            state.name: rows.where((r) => r.decision.state == state).length,
        },
        'rows': [for (final row in rows) row.toJson()],
      };
}

/// Supplies evidence seeds. Implementations must only SELECTs.
abstract class OfficialAnkiSourceEvidenceReader {
  Future<List<OfficialAnkiSourceEvidence>> loadEvidence({
    required String profileId,
  });
}

/// Fixture / in-memory reader for unit tests.
class ListOfficialAnkiSourceEvidenceReader
    implements OfficialAnkiSourceEvidenceReader {
  ListOfficialAnkiSourceEvidenceReader(this._rows);

  final List<OfficialAnkiSourceEvidence> _rows;

  @override
  Future<List<OfficialAnkiSourceEvidence>> loadEvidence({
    required String profileId,
  }) async {
    return [
      for (final row in _rows)
        if (row.profileId == profileId) row,
    ];
  }
}

/// Catalog-backed reader: official sources + migration links only.
/// Never writes; never opens the Anki Collection for mutation.
class CatalogOfficialAnkiSourceEvidenceReader
    implements OfficialAnkiSourceEvidenceReader {
  CatalogOfficialAnkiSourceEvidenceReader(this._database);

  final OfficialAnkiDatabase _database;

  @override
  Future<List<OfficialAnkiSourceEvidence>> loadEvidence({
    required String profileId,
  }) async {
    final sourceDao = OfficialAnkiSourceDao(_database);
    final sources = sourceDao.listSources(profileId);
    final db = _database.handle;
    final out = <OfficialAnkiSourceEvidence>[];

    for (final source in sources) {
      final cardCount = sourceDao.cardCount(source.sourceId);
      final proj = db.select(
        'SELECT projected_card_count, state FROM anki_source_projection_state '
        'WHERE source_id = ?',
        [source.sourceId],
      );
      final projected = proj.isEmpty
          ? 0
          : (proj.first['projected_card_count'] as num?)?.toInt() ?? 0;
      final mig = db.select(
        'SELECT recorded_kind, official_source_id, state, legacy_import_id, '
        'source_hash FROM legacy_anki_migrations '
        'WHERE profile_id = ? AND official_source_id = ? '
        'ORDER BY updated_at_millis DESC LIMIT 1',
        [profileId, source.sourceId],
      );
      String? recordedKind;
      String? migState;
      String? importId;
      String? migSourceId;
      if (mig.isNotEmpty) {
        recordedKind = mig.first['recorded_kind'] as String?;
        migState = mig.first['state'] as String?;
        importId = mig.first['legacy_import_id'] as String?;
        migSourceId = mig.first['official_source_id'] as String?;
      }
      out.add(
        OfficialAnkiSourceEvidence(
          profileId: profileId,
          sourceId: source.sourceId,
          importId: importId,
          sourceHash: source.sourceHash,
          migrationRecordedKind: recordedKind,
          migrationOfficialSourceId: migSourceId,
          migrationState: migState,
          officialSourceState: source.state,
          officialCardCount: cardCount,
          collectionPresent: cardCount > 0,
          projectionPresent: projected > 0,
          placementCount: projected,
          identityRowCount: projected,
        ),
      );
    }
    return out;
  }
}

/// Read-only census: classify every evidence row; never mutate DB / Collection.
class OfficialAnkiSourceCensusService {
  const OfficialAnkiSourceCensusService({
    this.reconciler = const OfficialAnkiSourceReconciler(),
  });

  final OfficialAnkiSourceReconciler reconciler;

  Future<OfficialAnkiSourceCensusReport> collect({
    required OfficialAnkiSourceEvidenceReader reader,
    required String profileId,
    int? nowMillis,
  }) async {
    final seeds = await reader.loadEvidence(profileId: profileId);
    final rows = <OfficialAnkiSourceCensusRow>[
      for (final evidence in seeds)
        OfficialAnkiSourceCensusRow(
          evidence: evidence,
          decision: reconciler.classify(evidence),
        ),
    ];
    return OfficialAnkiSourceCensusReport(
      generatedAtMillis: nowMillis ?? DateTime.now().millisecondsSinceEpoch,
      rows: rows,
    );
  }
}

/// Helper: open a journal for a repair without applying mutations yet.
OfficialAnkiReconciliationJournalEntry beginReconciliationJournal({
  required OfficialAnkiReconciliationJournalDao dao,
  required OfficialAnkiSourceEvidence evidence,
  required OfficialAnkiSourceReconcileDecision decision,
  required String operationId,
  required int nowMillis,
  OfficialAnkiReconcileRetryPolicy retryPolicy =
      OfficialAnkiReconcileRetryPolicy.resumeFromStep,
  OfficialAnkiReconcileRollbackPolicy rollbackPolicy =
      OfficialAnkiReconcileRollbackPolicy.restoreBackup,
}) {
  final entry = OfficialAnkiReconciliationJournalEntry(
    operationId: operationId,
    profileId: evidence.profileId,
    sourceId: evidence.sourceId,
    importId: evidence.importId,
    beforeState: decision.state,
    evidenceHash: decision.evidenceHash,
    intendedOwner: decision.intendedOwner,
    currentStep: OfficialAnkiReconcileJournalStep.scanned,
    retryPolicy: retryPolicy,
    rollbackPolicy: rollbackPolicy,
    updatedAtMillis: nowMillis,
    createdAtMillis: nowMillis,
  );
  dao.insert(entry);
  return entry;
}
