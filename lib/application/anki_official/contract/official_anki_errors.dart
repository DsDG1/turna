enum OfficialAnkiErrorCode {
  unsupportedPlatform,
  libraryMissing,
  symbolMissing,
  invalidHandle,
  unimplemented,
  backendPanic,
  invalidArgument,
  invalidState,
  collectionAlreadyOpen,
  collectionLocked,
  collectionOpenFailed,
  packageNotFound,
  packageInvalid,
  importCancelled,
  cardNotFound,
  renderFailed,
  typedFieldNotFound,
  typedClozeEmpty,
  pageTokenStale,
  contractVersionMismatch,
  ioError,
  collectionCorrupt,
  internalError,
  capabilityMissing,
  needsReconciliation,
  projectionSnapshotStale,
  projectionSourceChanged,
  queueEmpty,
  schedulingContextStale,
  answerFailed,
  answerCommitUnknown,
  undoUnavailable,
  redoUnavailable,
  deckNotFound,
  schedulerBusy,
  schedulerCapabilityMissing,
  unknown,
}

class OfficialAnkiException implements Exception {
  const OfficialAnkiException({
    required this.code,
    required this.messageKey,
    this.recoverable = false,
    this.debugDetails,
  });

  final OfficialAnkiErrorCode code;
  final String messageKey;
  final bool recoverable;
  final String? debugDetails;

  factory OfficialAnkiException.fromJson(Map<String, Object?> json) {
    return OfficialAnkiException(
      code: officialAnkiErrorCodeFromName(json['code'] as String?),
      messageKey: json['messageKey'] as String? ?? 'official_anki.backend_error',
      recoverable: json['recoverable'] == true,
      debugDetails: json['debugDetails'] as String?,
    );
  }

  @override
  String toString() {
    final extra = debugDetails == null ? '' : ' $debugDetails';
    return 'OfficialAnkiException(${code.name}: $messageKey$extra)';
  }
}

OfficialAnkiErrorCode officialAnkiErrorCodeFromName(String? name) {
  switch (name) {
    case 'UNIMPLEMENTED':
      return OfficialAnkiErrorCode.unimplemented;
    case 'INVALID_HANDLE':
      return OfficialAnkiErrorCode.invalidHandle;
    case 'INVALID_ARGUMENT':
      return OfficialAnkiErrorCode.invalidArgument;
    case 'BACKEND_PANIC':
      return OfficialAnkiErrorCode.backendPanic;
    case 'INVALID_STATE':
      return OfficialAnkiErrorCode.invalidState;
    case 'COLLECTION_ALREADY_OPEN':
      return OfficialAnkiErrorCode.collectionAlreadyOpen;
    case 'COLLECTION_LOCKED':
      return OfficialAnkiErrorCode.collectionLocked;
    case 'COLLECTION_OPEN_FAILED':
      return OfficialAnkiErrorCode.collectionOpenFailed;
    case 'PACKAGE_NOT_FOUND':
      return OfficialAnkiErrorCode.packageNotFound;
    case 'PACKAGE_INVALID':
      return OfficialAnkiErrorCode.packageInvalid;
    case 'IMPORT_CANCELLED':
      return OfficialAnkiErrorCode.importCancelled;
    case 'CARD_NOT_FOUND':
      return OfficialAnkiErrorCode.cardNotFound;
    case 'RENDER_FAILED':
      return OfficialAnkiErrorCode.renderFailed;
    case 'TYPED_FIELD_NOT_FOUND':
      return OfficialAnkiErrorCode.typedFieldNotFound;
    case 'TYPED_CLOZE_EMPTY':
      return OfficialAnkiErrorCode.typedClozeEmpty;
    case 'PAGE_TOKEN_STALE':
      return OfficialAnkiErrorCode.pageTokenStale;
    case 'PROJECTION_SNAPSHOT_STALE':
      return OfficialAnkiErrorCode.projectionSnapshotStale;
    case 'PROJECTION_SOURCE_CHANGED':
      return OfficialAnkiErrorCode.projectionSourceChanged;
    case 'QUEUE_EMPTY':
      return OfficialAnkiErrorCode.queueEmpty;
    case 'SCHEDULING_CONTEXT_STALE':
      return OfficialAnkiErrorCode.schedulingContextStale;
    case 'ANSWER_FAILED':
      return OfficialAnkiErrorCode.answerFailed;
    case 'ANSWER_COMMIT_UNKNOWN':
      return OfficialAnkiErrorCode.answerCommitUnknown;
    case 'UNDO_UNAVAILABLE':
      return OfficialAnkiErrorCode.undoUnavailable;
    case 'REDO_UNAVAILABLE':
      return OfficialAnkiErrorCode.redoUnavailable;
    case 'DECK_NOT_FOUND':
      return OfficialAnkiErrorCode.deckNotFound;
    case 'SCHEDULER_BUSY':
      return OfficialAnkiErrorCode.schedulerBusy;
    case 'SCHEDULER_CAPABILITY_MISSING':
      return OfficialAnkiErrorCode.schedulerCapabilityMissing;
    case 'CONTRACT_VERSION_MISMATCH':
      return OfficialAnkiErrorCode.contractVersionMismatch;
    case 'IO_ERROR':
      return OfficialAnkiErrorCode.ioError;
    case 'COLLECTION_CORRUPT':
      return OfficialAnkiErrorCode.collectionCorrupt;
    case 'INTERNAL_ERROR':
      return OfficialAnkiErrorCode.internalError;
    default:
      return OfficialAnkiErrorCode.unknown;
  }
}
