import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_backup_manifest.dart';
import 'package:turna/application/anki_official/migration/official_anki_census.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_saga.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/data/anki_owner_authority_dao.dart';

/// Census / reconciler status that may enter the W8 single-source saga.
const kCleanLegacyCensusStatus = 'cleanLegacy';

/// Marker written into [LegacyAnkiMigrationRow] error fields when the shadow
/// Legacy rows are scheduled for post-release cleanup (doc 34 §12.4 last step).
const kLegacyShadowCleanupAfterRelease = 'cleanup-after-release';

/// Next journal action for [OfficialLegacySourceMigrationSaga.resume].
enum OfficialLegacyMigrationResumeAction {
  snapshotBackup,
  importOrReconstruct,
  chooseSchedulingPolicy,
  mapAndProject,
  compare,
  freezeLegacy,
  atomicOwnerSwitch,
  smokeOfficial,
  markCleanupAfterRelease,
  keepLegacyReadOnlyTerminal,
  done,
  rollbackOrUserAction,
  failedRecoverable,
}

/// Resumable single-source Legacy → Official migration saga (doc 34 §12.4).
///
/// ```text
/// census cleanLegacy
///   -> snapshot/backup
///   -> create official pending source
///   -> import/reconstruct cards
///   -> migrate/choose scheduling policy
///   -> build projection + identity
///   -> compare cardinality/fingerprint/sample rendering
///   -> freeze legacy writer
///   -> atomically switch persisted owner
///   -> smoke official due/review
///   -> mark legacy shadow cleanup-after-release
/// ```
///
/// Owner switch is a single CAS transition (`cutoverReady` → `cutover`).
/// Rollback before that transition restores Legacy as the active writer;
/// after switch, rollback never re-enables dual-write.
class OfficialLegacySourceMigrationSaga {
  const OfficialLegacySourceMigrationSaga({
    required this.dao,
    required this.coordinator,
    this.backupService = const LegacyAnkiBackupService(),
    this.dryRunSaga = const LegacyAnkiDryRunSaga(),
    this.authorityDao,
  });

  final OfficialAnkiMigrationDao dao;
  final OfficialAnkiOperationCoordinator coordinator;
  final LegacyAnkiBackupService backupService;
  final LegacyAnkiDryRunSaga dryRunSaga;

  /// CourseDatabase owner authority (plan 34 D3). When present, freeze is
  /// a REAL fence CAS and the owner switch commits here first — the
  /// catalog's `legacy_anki_migrations` becomes a replayable journal
  /// mirror and never the production routing fact.
  final AnkiOwnerAuthorityDao? authorityDao;

  /// Step 1 — accept a census-classified `cleanLegacy` source into the journal.
  void beginFromCleanLegacyCensus({
    required String migrationId,
    required String profileId,
    required String legacyImportId,
    required String sourceHash,
    required LegacyAnkiSchedulingPolicy policy,
    required bool policyConfirmedByUser,
    String censusStatus = kCleanLegacyCensusStatus,
    int legacyCardCount = 0,
    bool losslessScheduleMapAvailable = false,
    int? nowMillis,
  }) {
    if (censusStatus != kCleanLegacyCensusStatus) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.migration_not_clean_legacy',
        debugDetails: censusStatus,
      );
    }
    _requireExplicitPolicyWhenNeeded(
      policy: policy,
      policyConfirmedByUser: policyConfirmedByUser,
      losslessScheduleMapAvailable: losslessScheduleMapAvailable,
    );

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
      // Idempotent resume: already past detected.
      if (existing.state == LegacyAnkiMigrationState.detected) {
        dao.transition(
          migrationId: existing.migrationId,
          expected: LegacyAnkiMigrationState.detected,
          next: LegacyAnkiMigrationState.awaitingPackage,
          nowMillis: now,
        );
        return;
      }
      if (existing.state == LegacyAnkiMigrationState.needsUserAction ||
          existing.state == LegacyAnkiMigrationState.failedRecoverable) {
        dao.transition(
          migrationId: existing.migrationId,
          expected: existing.state,
          next: LegacyAnkiMigrationState.awaitingPackage,
          nowMillis: now,
        );
      }
    } catch (_) {
      coordinator.release(OfficialAnkiOperationPhase.migrating);
      rethrow;
    }
  }

  /// Step 2 — validate package hash and write a recoverable snapshot/backup.
  Future<bool> snapshotAndBackup({
    required String migrationId,
    required File pickedFile,
    required String expectedSourceHash,
    required OfficialAnkiPaths paths,
    List<LegacyAnkiCardIdentity>? legacyCards,
    LegacyAnkiCensusReport? census,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final row = _requireRow(migrationId);
    _requireState(
      row,
      const {
        LegacyAnkiMigrationState.awaitingPackage,
        LegacyAnkiMigrationState.validatingSource,
        LegacyAnkiMigrationState.backingUp,
      },
    );

    if (row.state == LegacyAnkiMigrationState.awaitingPackage) {
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
      final computed =
          sha256.convert(await pickedFile.readAsBytes()).toString();
      if (computed != expectedSourceHash) {
        dao.transition(
          migrationId: migrationId,
          expected: LegacyAnkiMigrationState.awaitingPackage,
          next: LegacyAnkiMigrationState.needsUserAction,
          nowMillis: now,
          errorCode: 'official_anki.migration_package_mismatch',
          errorMessage:
              'Picked package sha256 does not match census sourceHash',
        );
        return false;
      }
      dao.transition(
        migrationId: migrationId,
        expected: LegacyAnkiMigrationState.awaitingPackage,
        next: LegacyAnkiMigrationState.validatingSource,
        nowMillis: now,
      );
    }

    final current = _requireRow(migrationId);
    if (current.state == LegacyAnkiMigrationState.validatingSource) {
      dao.transition(
        migrationId: migrationId,
        expected: LegacyAnkiMigrationState.validatingSource,
        next: LegacyAnkiMigrationState.backingUp,
        nowMillis: now,
      );
    }

    final manifest = census != null
        ? backupService.generateFromCensus(
            census: census,
            officialBackupId: 'bak-$migrationId',
            createdAtMillis: now,
          )
        : backupService.generate(
            importCount: 1,
            noteCount:
                legacyCards?.map((c) => c.legacyNoteId).toSet().length ?? 0,
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

  /// Steps 3–4 — create Official pending source via importer / reconstruct path.
  Future<String> importOrReconstruct({
    required String migrationId,
    required String packagePath,
    required OfficialAnkiImporter importer,
    String? displayName,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final row = _requireRow(migrationId);
    if (row.schedulingPolicy.abandonsOfficialCutover) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.policy_keeps_legacy_read_only',
        debugDetails: 'keepLegacyReadOnly skips Official import',
      );
    }
    _requireState(row, {LegacyAnkiMigrationState.backingUp});

    dao.transition(
      migrationId: migrationId,
      expected: LegacyAnkiMigrationState.backingUp,
      next: LegacyAnkiMigrationState.importingOfficial,
      nowMillis: now,
    );

    final result = await importer.importFile(
      packagePath: packagePath,
      displayName: displayName ?? 'legacy-source-migration',
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

  /// Step 5 — apply / re-confirm scheduling policy. Never silent-reset.
  ///
  /// When [losslessScheduleMapAvailable] is false, [policyConfirmedByUser]
  /// must be true and [policy] must be one of the three explicit choices.
  Future<bool> chooseSchedulingPolicy({
    required String migrationId,
    required LegacyAnkiSchedulingPolicy policy,
    required bool policyConfirmedByUser,
    required bool losslessScheduleMapAvailable,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final row = _requireRow(migrationId);
    _requireExplicitPolicyWhenNeeded(
      policy: policy,
      policyConfirmedByUser: policyConfirmedByUser,
      losslessScheduleMapAvailable: losslessScheduleMapAvailable,
    );

    if (policy.abandonsOfficialCutover) {
      // Terminal: freeze as needsUserAction with explicit keep-legacy reason.
      final from = row.state;
      if (from == LegacyAnkiMigrationState.completed ||
          from == LegacyAnkiMigrationState.needsUserAction) {
        return true;
      }
      // Prefer leaving journal in needsUserAction so UI can export / re-import.
      if (legacyAnkiMigrationAllowsTransition(
        from: from,
        to: LegacyAnkiMigrationState.needsUserAction,
      )) {
        dao.transition(
          migrationId: migrationId,
          expected: from,
          next: LegacyAnkiMigrationState.needsUserAction,
          nowMillis: now,
          errorCode: 'official_anki.keep_legacy_read_only',
          errorMessage: policy.userVisibleDescription,
        );
      }
      return true;
    }

    // Policy already persisted at insertDetected; re-assert for resume safety.
    if (row.schedulingPolicy != policy) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.scheduling_policy_mismatch',
        debugDetails:
            'journal=${row.schedulingPolicy.name} chosen=${policy.name}',
      );
    }
    return true;
  }

  /// Steps 5b–6 — map cards and build projection + identity.
  Future<bool> mapCardsAndProject({
    required String migrationId,
    required List<LegacyAnkiCardIdentity> legacyCards,
    required List<OfficialAnkiCardIdentity> officialCards,
    bool sameTrustedPackage = false,
    Future<void> Function()? projectionAction,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    var row = _requireRow(migrationId);
    if (row.schedulingPolicy.abandonsOfficialCutover) {
      return chooseSchedulingPolicy(
        migrationId: migrationId,
        policy: row.schedulingPolicy,
        policyConfirmedByUser: true,
        losslessScheduleMapAvailable: false,
        nowMillis: now,
      );
    }

    if (row.state == LegacyAnkiMigrationState.indexingOfficial) {
      dao.transition(
        migrationId: migrationId,
        expected: LegacyAnkiMigrationState.indexingOfficial,
        next: LegacyAnkiMigrationState.mappingCards,
        nowMillis: now,
      );
    }

    row = _requireRow(migrationId);
    if (row.state == LegacyAnkiMigrationState.mappingCards) {
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
    }

    row = _requireRow(migrationId);
    if (row.state == LegacyAnkiMigrationState.projectingCourse) {
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
    return true;
  }

  /// Step 7 — compare cardinality / fingerprint gates before freeze.
  Future<bool> compareCardinality({
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
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final row = _requireRow(migrationId);
    _requireState(row, {LegacyAnkiMigrationState.verifying});

    final mismatches = <String>[];
    if (officialCardCount < legacyCardCount) {
      mismatches
          .add('cards official=$officialCardCount < legacy=$legacyCardCount');
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
        'projection $projectionItemCount!=matched $matchedCount/'
        'official $officialCardCount',
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
    return true;
  }

  /// Step 8 — freeze Legacy writer (still Official-not-owner until switch).
  ///
  /// With an [authorityDao] this performs the REAL freeze: the source's
  /// write fence CAS open→frozen in the CourseDatabase authority. From
  /// this point the Legacy write fence rejects ordinary mutators (plan 34
  /// §R4-1) — the freeze is a behavior, not a comment.
  Future<void> freezeLegacyWriter({
    required String migrationId,
    int? nowMillis,
  }) async {
    final row = _requireRow(migrationId);
    // cutoverReady is the freeze gate; already there after compare.
    _requireState(row, {LegacyAnkiMigrationState.cutoverReady});
    final authority = authorityDao;
    if (authority == null) return;
    final officialSourceId = row.officialSourceId;
    if (officialSourceId == null || officialSourceId.isEmpty) {
      throw StateError(
        'freeze requires an official source id (migration $migrationId)',
      );
    }
    final courseId = _courseIdFor(officialSourceId);
    // Ensure the authority row exists (legacy backend, still open).
    if (await authority.findByCourseId(courseId) == null) {
      await authority.upsertSource(
        courseId: courseId,
        profileId: row.profileId,
        sourceId: officialSourceId,
        backendKind: 'legacyTurna',
        displayName: row.legacyImportId,
        sourceHash: '',
        sourceFingerprint: '',
        state: AnkiSourceVisibility.active,
      );
    }
    final transitionId = 'tr-$migrationId';
    if (await authority.transitionById(transitionId) == null &&
        await authority.inFlightTransition(courseId) == null) {
      await authority.beginTransition(
        transitionId: transitionId,
        profileId: row.profileId,
        legacyImportId: row.legacyImportId,
        officialSourceId: officialSourceId,
        courseId: courseId,
        fromBackend: 'legacyTurna',
        toBackend: 'official',
        policy: row.schedulingPolicy.name,
      );
    }
    // Fast-forward the authority phase machine to frozen (idempotent:
    // CAS conflicts mean an earlier resume already advanced past a step).
    const path = [
      (
        OwnerTransitionPhase.discovered,
        OwnerTransitionPhase.awaitingUserPolicy
      ),
      (OwnerTransitionPhase.awaitingUserPolicy, OwnerTransitionPhase.backingUp),
      (OwnerTransitionPhase.backingUp, OwnerTransitionPhase.importingOfficial),
      (
        OwnerTransitionPhase.importingOfficial,
        OwnerTransitionPhase.verifyingIdentity
      ),
      (
        OwnerTransitionPhase.verifyingIdentity,
        OwnerTransitionPhase.projectionStaging
      ),
      (
        OwnerTransitionPhase.projectionStaging,
        OwnerTransitionPhase.cutoverReady
      ),
      (OwnerTransitionPhase.cutoverReady, OwnerTransitionPhase.frozen),
    ];
    for (final (from, to) in path) {
      try {
        await authority.advancePhase(
          transitionId: transitionId,
          from: from,
          to: to,
        );
      } on OwnerAuthorityConflict {
        // Already advanced by a previous resume.
      }
    }
    try {
      await authority.compareAndSetWriteFence(
        courseId: courseId,
        expected: AnkiWriteFence.open,
        next: AnkiWriteFence.frozen,
      );
    } on OwnerAuthorityConflict {
      // Already frozen (resume after crash between phase and fence).
    }
  }

  String _courseIdFor(String officialSourceId) => 'course-$officialSourceId';

  /// Step 9 — single commit point: persist Official owner.
  ///
  /// With an [authorityDao], the AUTHORITATIVE commit happens in the
  /// CourseDatabase first (`commitOwnership`: backend_kind, generation,
  /// officialOnly fence and the transition's observing phase in one
  /// transaction). The catalog transition below is the journal mirror —
  /// a mirror failure never regresses the owner (plan 34 D3 / §R4-2).
  Future<void> atomicOwnerSwitch({
    required String migrationId,
    int officialMutationCountAtCutover = 0,
    void Function()? onCutover,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final row = _requireRow(migrationId);
    _requireState(row, {LegacyAnkiMigrationState.cutoverReady});

    final authority = authorityDao;
    final officialSourceId = row.officialSourceId;
    if (authority != null) {
      if (officialSourceId == null || officialSourceId.isEmpty) {
        throw StateError(
          'owner switch requires an official source id '
          '(migration $migrationId)',
        );
      }
      final courseId = _courseIdFor(officialSourceId);
      final transitionId = 'tr-$migrationId';
      try {
        await authority.advancePhase(
          transitionId: transitionId,
          from: OwnerTransitionPhase.frozen,
          to: OwnerTransitionPhase.committing,
        );
      } on OwnerAuthorityConflict {
        // Resumed mid-commit: the CAS in commitOwnership re-verifies.
      }
      await authority.commitOwnership(
        transitionId: transitionId,
        courseId: courseId,
      );
    }

    dao.atomicCutoverTransition(
      migrationId: migrationId,
      officialMutationCountAtCutover: officialMutationCountAtCutover,
      nowMillis: now,
      onTransaction: onCutover,
    );
  }

  /// Step 10 — smoke Official due/review path, then enter observing.
  Future<bool> smokeOfficialReview({
    required String migrationId,
    Future<bool> Function()? smokeAction,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final row = _requireRow(migrationId);
    _requireState(row, {LegacyAnkiMigrationState.cutover});

    if (smokeAction != null) {
      final ok = await smokeAction();
      if (!ok) {
        dao.transition(
          migrationId: migrationId,
          expected: LegacyAnkiMigrationState.cutover,
          next: LegacyAnkiMigrationState.failedRecoverable,
          nowMillis: now,
          errorCode: 'official_anki.smoke_failed',
          errorMessage: 'Official due/review smoke failed after cutover',
        );
        return false;
      }
    }

    dao.transition(
      migrationId: migrationId,
      expected: LegacyAnkiMigrationState.cutover,
      next: LegacyAnkiMigrationState.observing,
      nowMillis: now,
    );
    return true;
  }

  /// Step 11 — mark Legacy shadow for cleanup-after-release (not physical delete).
  void markLegacyShadowCleanupAfterRelease({
    required String migrationId,
    int? nowMillis,
  }) {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final row = _requireRow(migrationId);
    _requireState(row, {LegacyAnkiMigrationState.observing});

    dao.transition(
      migrationId: migrationId,
      expected: LegacyAnkiMigrationState.observing,
      next: LegacyAnkiMigrationState.completed,
      nowMillis: now,
      errorCode: kLegacyShadowCleanupAfterRelease,
      errorMessage:
          'Legacy shadow retained until one formal release observation (W9 HOLD)',
    );
  }

  /// Journal resume: map persisted state → next §12.4 action.
  OfficialLegacyMigrationResumeAction resume({required String migrationId}) {
    final row = dao.findById(migrationId);
    if (row == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.migration_missing',
      );
    }
    if (row.schedulingPolicy.abandonsOfficialCutover &&
        row.state != LegacyAnkiMigrationState.completed) {
      return OfficialLegacyMigrationResumeAction.keepLegacyReadOnlyTerminal;
    }
    switch (row.state) {
      case LegacyAnkiMigrationState.detected:
      case LegacyAnkiMigrationState.awaitingPackage:
      case LegacyAnkiMigrationState.validatingSource:
        return OfficialLegacyMigrationResumeAction.snapshotBackup;
      case LegacyAnkiMigrationState.backingUp:
        return OfficialLegacyMigrationResumeAction.importOrReconstruct;
      case LegacyAnkiMigrationState.importingOfficial:
      case LegacyAnkiMigrationState.indexingOfficial:
        return OfficialLegacyMigrationResumeAction.chooseSchedulingPolicy;
      case LegacyAnkiMigrationState.mappingCards:
      case LegacyAnkiMigrationState.projectingCourse:
        return OfficialLegacyMigrationResumeAction.mapAndProject;
      case LegacyAnkiMigrationState.verifying:
        return OfficialLegacyMigrationResumeAction.compare;
      case LegacyAnkiMigrationState.cutoverReady:
        return OfficialLegacyMigrationResumeAction.atomicOwnerSwitch;
      case LegacyAnkiMigrationState.cutover:
        return OfficialLegacyMigrationResumeAction.smokeOfficial;
      case LegacyAnkiMigrationState.observing:
        return OfficialLegacyMigrationResumeAction.markCleanupAfterRelease;
      case LegacyAnkiMigrationState.completed:
        return OfficialLegacyMigrationResumeAction.done;
      case LegacyAnkiMigrationState.failedRecoverable:
        return OfficialLegacyMigrationResumeAction.failedRecoverable;
      case LegacyAnkiMigrationState.needsUserAction:
      case LegacyAnkiMigrationState.rollbackRequired:
      case LegacyAnkiMigrationState.rolledBackLegacy:
      case LegacyAnkiMigrationState.rollbackEligible:
      case LegacyAnkiMigrationState.noLegacyScheduleRollback:
        return OfficialLegacyMigrationResumeAction.rollbackOrUserAction;
    }
  }

  /// Rollback rules (doc 34 §12.5):
  /// - before owner switch: full Legacy restore path (`rolledBackLegacy`);
  /// - after switch with mutation==0: UI/code rollback only (`rollbackEligible`);
  /// - after switch with mutation>0: no Legacy schedule rollback.
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
        // UI/code rollback only — do not re-enable Legacy dual-write.
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
      return;
    }
    if (currentState == LegacyAnkiMigrationState.completed) {
      // Cleanup-after-release already marked; schedule rollback is closed.
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.no_legacy_schedule_rollback',
        debugDetails: 'completed cleanup-after-release',
      );
    }

    // Pre-switch: restore Legacy journal ownership.
    dao.setRecordedKind(
      migrationId: migrationId,
      recordedKind: 'legacy',
      nowMillis: now,
    );
    dao.transition(
      migrationId: migrationId,
      expected: currentState,
      next: LegacyAnkiMigrationState.rolledBackLegacy,
      nowMillis: now,
    );
  }

  void releaseLease() {
    coordinator.release(OfficialAnkiOperationPhase.migrating);
  }

  static bool isCleanupAfterReleaseMarked(LegacyAnkiMigrationRow row) {
    return row.state == LegacyAnkiMigrationState.completed;
  }

  void _requireExplicitPolicyWhenNeeded({
    required LegacyAnkiSchedulingPolicy policy,
    required bool policyConfirmedByUser,
    required bool losslessScheduleMapAvailable,
  }) {
    if (losslessScheduleMapAvailable) return;
    if (!policyConfirmedByUser) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.scheduling_policy_requires_user_choice',
        debugDetails:
            'lossless map unavailable; present ${LegacyAnkiSchedulingPolicy.values.map((p) => p.userVisibleLabel).join(' | ')}',
      );
    }
    // All three enum values are valid explicit choices; none is applied
    // implicitly. resetAsNew is allowed only because the user confirmed it.
    assert(
      policy == LegacyAnkiSchedulingPolicy.preservePackageScheduling ||
          policy == LegacyAnkiSchedulingPolicy.resetAsNew ||
          policy == LegacyAnkiSchedulingPolicy.keepLegacyReadOnly,
    );
  }

  LegacyAnkiMigrationRow _requireRow(String migrationId) {
    final row = dao.findById(migrationId);
    if (row == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.migration_missing',
      );
    }
    return row;
  }

  void _requireState(
    LegacyAnkiMigrationRow row,
    Set<LegacyAnkiMigrationState> allowed,
  ) {
    if (allowed.contains(row.state)) return;
    throw OfficialAnkiException(
      code: OfficialAnkiErrorCode.invalidState,
      messageKey: 'official_anki.illegal_migration_transition',
      debugDetails: '${row.migrationId} at ${row.state.name}; expected one of '
          '${allowed.map((s) => s.name).join(",")}',
    );
  }
}
