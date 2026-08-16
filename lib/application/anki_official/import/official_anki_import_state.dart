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

enum OfficialAnkiSourceState {
  selected,
  hashing,
  preparing,
  backingUp,
  importingOfficial,
  indexingNotes,
  indexingCards,
  active,
  cancelRequested,
  cancelled,
  failedBeforeImport,
  failedAfterImport,
  needsReconciliation,
  recovering,
  rolledBack,
}

extension OfficialAnkiSourceStateWire on OfficialAnkiSourceState {
  String get wire {
    switch (this) {
      case OfficialAnkiSourceState.selected:
        return 'selected';
      case OfficialAnkiSourceState.hashing:
        return 'hashing';
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
      case OfficialAnkiSourceState.cancelRequested:
        return 'cancel_requested';
      case OfficialAnkiSourceState.cancelled:
        return 'cancelled';
      case OfficialAnkiSourceState.failedBeforeImport:
        return 'failed_before_import';
      case OfficialAnkiSourceState.failedAfterImport:
        return 'failed_after_import';
      case OfficialAnkiSourceState.needsReconciliation:
        return 'needs_reconciliation';
      case OfficialAnkiSourceState.recovering:
        return 'recovering';
      case OfficialAnkiSourceState.rolledBack:
        return 'rolled_back';
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
      this == OfficialAnkiSourceState.failedAfterImport ||
      this == OfficialAnkiSourceState.rolledBack ||
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
  if (state == OfficialAnkiSourceState.hashing ||
      state == OfficialAnkiSourceState.selected ||
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
    return const OfficialAnkiRecoveryDecision(
      action: OfficialAnkiRecoveryAction.resume,
      state: OfficialAnkiSourceState.recovering,
    );
  }
  if (state == OfficialAnkiSourceState.cancelRequested) {
    return const OfficialAnkiRecoveryDecision(
      action: OfficialAnkiRecoveryAction.leave,
      state: OfficialAnkiSourceState.cancelled,
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
