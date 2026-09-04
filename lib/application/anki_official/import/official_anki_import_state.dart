abstract class OfficialAnkiImporter {
  Future<OfficialAnkiImportResult> importFile({
    required String packagePath,
    required String displayName,
    String? requestId,
    bool cancel = false,
  });
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
  previewReady,
  staging,
  active,
  cancelled,
  failedBeforeImport,
  needsReconciliation,
  cancelRequested,
  rollbackPending,
  rolledBack,
  pendingCleanup,
  retiring,
  retired,
  quarantined,
  completed,
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
      case OfficialAnkiSourceState.previewReady:
        return 'preview_ready';
      case OfficialAnkiSourceState.staging:
        return 'staging';
      case OfficialAnkiSourceState.active:
        return 'active';
      case OfficialAnkiSourceState.cancelled:
        return 'cancelled';
      case OfficialAnkiSourceState.failedBeforeImport:
        return 'failed_before_import';
      case OfficialAnkiSourceState.needsReconciliation:
        return 'needs_reconciliation';
      case OfficialAnkiSourceState.cancelRequested:
        return 'cancel_requested';
      case OfficialAnkiSourceState.rollbackPending:
        return 'rollback_pending';
      case OfficialAnkiSourceState.rolledBack:
        return 'rolled_back';
      case OfficialAnkiSourceState.pendingCleanup:
        return 'pending_cleanup';
      case OfficialAnkiSourceState.retiring:
        // ADR 0043 D6: single-ledger transaction state — the user already
        // saw removal; a job drives the engine delete to completion.
        return 'retiring';
      case OfficialAnkiSourceState.retired:
        return 'retired';
      case OfficialAnkiSourceState.quarantined:
        return 'quarantined';
      case OfficialAnkiSourceState.completed:
        return 'completed';
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
      this == OfficialAnkiSourceState.needsReconciliation ||
      this == OfficialAnkiSourceState.rolledBack ||
      this == OfficialAnkiSourceState.retired ||
      this == OfficialAnkiSourceState.quarantined ||
      this == OfficialAnkiSourceState.completed;

  bool get isActive => this == OfficialAnkiSourceState.active;

  bool get isPreviewReady => this == OfficialAnkiSourceState.previewReady;

  bool get allowsPreview =>
      this == OfficialAnkiSourceState.previewReady ||
      this == OfficialAnkiSourceState.active;
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
