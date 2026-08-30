/// Doc 41 lifecycle vocabulary. Catalog source rows use [sourceWire];
/// import attempts use the finer [OfficialAnkiSourceState] in
/// `official_anki_import_state.dart`.
library;

enum OfficialAnkiUserIntent {
  continueImport,
  discard,
  undecided;

  String get wire => switch (this) {
        OfficialAnkiUserIntent.continueImport => 'continue',
        OfficialAnkiUserIntent.discard => 'discard',
        OfficialAnkiUserIntent.undecided => 'undecided',
      };

  static OfficialAnkiUserIntent parse(String? raw) => switch (raw) {
        'continue' => OfficialAnkiUserIntent.continueImport,
        'discard' => OfficialAnkiUserIntent.discard,
        _ => OfficialAnkiUserIntent.undecided,
      };
}

enum OfficialAnkiNativeCommitState {
  notStarted,
  committed,
  unknown;

  String get wire => switch (this) {
        OfficialAnkiNativeCommitState.notStarted => 'not_started',
        OfficialAnkiNativeCommitState.committed => 'committed',
        OfficialAnkiNativeCommitState.unknown => 'unknown',
      };

  static OfficialAnkiNativeCommitState parse(String? raw) => switch (raw) {
        'not_started' => OfficialAnkiNativeCommitState.notStarted,
        'committed' => OfficialAnkiNativeCommitState.committed,
        _ => OfficialAnkiNativeCommitState.unknown,
      };
}

enum OfficialAnkiCheckpointFileState {
  creating,
  ready,
  restoring,
  released,
  quarantined;

  String get wire => name;

  static OfficialAnkiCheckpointFileState parse(String raw) =>
      OfficialAnkiCheckpointFileState.values.firstWhere(
        (value) => value.wire == raw,
        orElse: () => OfficialAnkiCheckpointFileState.quarantined,
      );
}

enum OfficialAnkiMaintenanceKind {
  mediaGc,
  metadataPrune,
  checkpointRelease,
  compactCollection,
  compactCatalog,
  compactCourse;

  String get wire => switch (this) {
        OfficialAnkiMaintenanceKind.mediaGc => 'media_gc',
        OfficialAnkiMaintenanceKind.metadataPrune => 'metadata_prune',
        OfficialAnkiMaintenanceKind.checkpointRelease => 'checkpoint_release',
        OfficialAnkiMaintenanceKind.compactCollection => 'compact_collection',
        OfficialAnkiMaintenanceKind.compactCatalog => 'compact_catalog',
        OfficialAnkiMaintenanceKind.compactCourse => 'compact_course',
      };

  static OfficialAnkiMaintenanceKind? tryParse(String raw) {
    for (final value in OfficialAnkiMaintenanceKind.values) {
      if (value.wire == raw) return value;
    }
    return null;
  }
}

enum OfficialAnkiMaintenanceJobState {
  pending,
  running,
  retryWait,
  completed,
  failed,
  quarantined;

  String get wire => switch (this) {
        OfficialAnkiMaintenanceJobState.pending => 'pending',
        OfficialAnkiMaintenanceJobState.running => 'running',
        OfficialAnkiMaintenanceJobState.retryWait => 'retry_wait',
        OfficialAnkiMaintenanceJobState.completed => 'completed',
        OfficialAnkiMaintenanceJobState.failed => 'failed',
        OfficialAnkiMaintenanceJobState.quarantined => 'quarantined',
      };
}

class OfficialAnkiUninstallResult {
  const OfficialAnkiUninstallResult({
    required this.sourceId,
    required this.phase,
    required this.logicalDeleteComplete,
    this.collectionCardsRequested = 0,
    this.collectionCardsRemoved = 0,
    this.collectionCardsRemaining = 0,
    this.appRowsRemaining = 0,
    this.mediaGcPending = false,
    this.compactPending = false,
    this.retryable = false,
    this.errorCode,
  });

  final String sourceId;
  final String phase;
  final bool logicalDeleteComplete;
  final int collectionCardsRequested;
  final int collectionCardsRemoved;
  final int collectionCardsRemaining;
  final int appRowsRemaining;
  final bool mediaGcPending;
  final bool compactPending;
  final bool retryable;
  final String? errorCode;

  bool get physicalMaintenanceComplete =>
      logicalDeleteComplete && !mediaGcPending && !compactPending;
}

class OfficialAnkiGcMediaResult {
  const OfficialAnkiGcMediaResult({
    this.scannedFiles = 0,
    this.unusedFiles = 0,
    this.removedFiles = 0,
    this.remainingFiles = 0,
    this.reclaimedBytes = 0,
    this.trashBytes = 0,
    this.collectionGeneration = 0,
    this.dryRun = false,
  });

  final int scannedFiles;
  final int unusedFiles;
  final int removedFiles;
  final int remainingFiles;
  final int reclaimedBytes;
  final int trashBytes;
  final int collectionGeneration;
  final bool dryRun;

  factory OfficialAnkiGcMediaResult.fromJson(Map<String, Object?> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return OfficialAnkiGcMediaResult(
      scannedFiles: n('scannedFiles'),
      unusedFiles: n('unusedFiles'),
      removedFiles: n('removedFiles'),
      remainingFiles: n('remainingFiles'),
      reclaimedBytes: n('reclaimedBytes'),
      trashBytes: n('trashBytes'),
      collectionGeneration: n('collectionGeneration'),
      dryRun: json['dryRun'] == true,
    );
  }
}

class OfficialAnkiPruneMetadataResult {
  const OfficialAnkiPruneMetadataResult({
    this.prunedNotetypes = 0,
    this.prunedDecks = 0,
    this.skipped = 0,
  });

  final int prunedNotetypes;
  final int prunedDecks;
  final int skipped;

  factory OfficialAnkiPruneMetadataResult.fromJson(Map<String, Object?> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return OfficialAnkiPruneMetadataResult(
      prunedNotetypes: n('prunedNotetypes'),
      prunedDecks: n('prunedDecks'),
      skipped: n('skipped'),
    );
  }
}

class OfficialAnkiCompactResult {
  const OfficialAnkiCompactResult({
    this.beforeBytes = 0,
    this.afterBytes = 0,
    this.freelistBytesBefore = 0,
    this.freelistBytesAfter = 0,
    this.elapsedMillis = 0,
    this.skippedReason,
  });

  final int beforeBytes;
  final int afterBytes;
  final int freelistBytesBefore;
  final int freelistBytesAfter;
  final int elapsedMillis;
  final String? skippedReason;

  int get reclaimedBytes =>
      beforeBytes > afterBytes ? beforeBytes - afterBytes : 0;

  factory OfficialAnkiCompactResult.fromJson(Map<String, Object?> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return OfficialAnkiCompactResult(
      beforeBytes: n('beforeBytes'),
      afterBytes: n('afterBytes'),
      freelistBytesBefore: n('freelistBytesBefore'),
      freelistBytesAfter: n('freelistBytesAfter'),
      elapsedMillis: n('elapsedMillis'),
      skippedReason: json['skippedReason'] as String?,
    );
  }
}

class OfficialAnkiPendingImport {
  const OfficialAnkiPendingImport({
    required this.sourceId,
    required this.attemptId,
    required this.displayName,
    required this.phase,
    this.cardCount = 0,
    this.lastError,
  });

  final String sourceId;
  final String attemptId;
  final String displayName;
  final String phase;
  final int cardCount;
  final String? lastError;
}

/// Doc 42 §4.1 attempt phase. Independent of [OfficialAnkiSourceState] on
/// `anki_sources.state`.
abstract final class OfficialAnkiAttemptPhase {
  static const created = 'created';
  static const stagingImporting = 'staging_importing';
  static const previewReady = 'preview_ready';
  static const cancelRequested = 'cancel_requested';
  static const cancelled = 'cancelled';
  static const committing = 'committing';
  static const receiptCommitted = 'receipt_committed';
  static const projecting = 'projecting';
  static const publishing = 'publishing';
  static const completed = 'completed';
  static const quarantined = 'quarantined';

  static const stagingCancellable = <String>{
    created,
    stagingImporting,
    previewReady,
    cancelRequested,
  };
}
