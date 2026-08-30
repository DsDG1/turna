import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';

abstract class OfficialAnkiImporter {
  Future<OfficialAnkiImportResult> importFile({
    required String packagePath,
    required String displayName,
    String? requestId,
    bool cancel = false,
  });
}

enum OfficialAnkiRecoveryAction { resume, retry, reconcile, leave }

class OfficialAnkiRecoveryDecision {
  const OfficialAnkiRecoveryDecision({
    required this.action,
    required this.state,
  });

  final OfficialAnkiRecoveryAction action;
  final OfficialAnkiSourceState state;
}

/// Doc 39 P5: the five never-produced values (`hashing`, `cancelRequested`,
/// `failedAfterImport`, `recovering`, `rolledBack`) were deleted. Old rows
/// on disk carrying those strings parse through the `orElse` fallback to
/// `needsReconciliation`; the attempt-table CHECK constraint is untouched.
enum OfficialAnkiSourceState {
  selected,
  preparing,
  backingUp,
  importingOfficial,
  indexingNotes,
  indexingCards,
  active,
  cancelled,
  failedBeforeImport,
  needsReconciliation,
}

extension OfficialAnkiSourceStateWire on OfficialAnkiSourceState {
  String get wire {
    switch (this) {
      case OfficialAnkiSourceState.selected:
        return 'selected';
      case OfficialAnkiSourceState.preparing:
        return 'preparing';
      case OfficialAnkiSourceState.backingUp:
        return 'backing_up';
      case OfficialAnkiSourceState.importingOfficial:
        return 'importing_official';
      case OfficialAnkiSourceState.indexingNotes:
        return 'indexing_notes';
      case OfficialAnkiSourceState.indexingCards:
        return 'indexing_cards';
      case OfficialAnkiSourceState.active:
        return 'active';
      case OfficialAnkiSourceState.cancelled:
        return 'cancelled';
      case OfficialAnkiSourceState.failedBeforeImport:
        return 'failed_before_import';
      case OfficialAnkiSourceState.needsReconciliation:
        return 'needs_reconciliation';
    }
  }

  static OfficialAnkiSourceState parse(String raw) {
    return OfficialAnkiSourceState.values.firstWhere(
      (value) => value.wire == raw,
      orElse: () => OfficialAnkiSourceState.needsReconciliation,
    );
  }

  bool get isTerminal =>
      this == OfficialAnkiSourceState.active ||
      this == OfficialAnkiSourceState.cancelled ||
      this == OfficialAnkiSourceState.failedBeforeImport ||
      this == OfficialAnkiSourceState.needsReconciliation;

  bool get isActive => this == OfficialAnkiSourceState.active;
}

OfficialAnkiRecoveryDecision decideOfficialAnkiRecovery(
  OfficialAnkiAttemptRow attempt,
) {
  final state = OfficialAnkiSourceStateWire.parse(attempt.state);
  if (state == OfficialAnkiSourceState.active) {
    return const OfficialAnkiRecoveryDecision(
      action: OfficialAnkiRecoveryAction.leave,
      state: OfficialAnkiSourceState.active,
    );
  }
  if (state == OfficialAnkiSourceState.selected ||
      state == OfficialAnkiSourceState.preparing ||
      state == OfficialAnkiSourceState.backingUp) {
    return const OfficialAnkiRecoveryDecision(
      action: OfficialAnkiRecoveryAction.retry,
      state: OfficialAnkiSourceState.failedBeforeImport,
    );
  }
  if (state == OfficialAnkiSourceState.importingOfficial &&
      !attempt.hasImportedNotes) {
    return const OfficialAnkiRecoveryDecision(
      action: OfficialAnkiRecoveryAction.reconcile,
      state: OfficialAnkiSourceState.needsReconciliation,
    );
  }
  if (state == OfficialAnkiSourceState.indexingNotes ||
      state == OfficialAnkiSourceState.indexingCards ||
      (state == OfficialAnkiSourceState.importingOfficial &&
          attempt.hasImportedNotes)) {
    // The decision `state` is only read on the leave path; resume reports
    // whatever resumeIndexing lands on (the `recovering` value it used to
    // carry was write-only and was deleted with the other dead states).
    return const OfficialAnkiRecoveryDecision(
      action: OfficialAnkiRecoveryAction.resume,
      state: OfficialAnkiSourceState.indexingCards,
    );
  }
  return const OfficialAnkiRecoveryDecision(
    action: OfficialAnkiRecoveryAction.reconcile,
    state: OfficialAnkiSourceState.needsReconciliation,
  );
}

enum OfficialAnkiFaultPoint {
  beforeHash,
  afterSourceBeforeCheckpoint,
  afterCheckpointBeforeImport,
  duringImportCancel,
  afterImportBeforeNoteIds,
  afterNoteIdsBeforeCards,
  afterMidBatchCursor,
  afterCardsBeforeActive,
  afterActiveRestart,
}

class OfficialAnkiImportResult {
  const OfficialAnkiImportResult({
    required this.sourceId,
    required this.attemptId,
    required this.state,
    required this.cardCount,
    required this.noteCount,
    this.alreadyImported = false,
    this.collectionNoteCount,
    this.collectionCardCount,
  });

  final String sourceId;
  final String attemptId;
  final OfficialAnkiSourceState state;
  final int cardCount;
  final int noteCount;
  final bool alreadyImported;
  final int? collectionNoteCount;
  final int? collectionCardCount;
}
