// Dart imports:
import 'dart:typed_data';

/// Pinned official Anki commit this spike was built against.
/// Runtime ENGINE_INFO (P0-006+) can confirm the linked rslib later.
const String kOfficialAnkiBackendCommit =
    '967aa0d578fc75181e292e95326f9b58698da25c';

const int kOfficialAnkiSpikeContractVersion = 1;

/// Native [TurnaAnkiResult.status] values from `bridge/src/abi.rs`.
abstract final class OfficialAnkiSpikeNativeStatus {
  static const int ok = 0;
  static const int unimplemented = 10;
  static const int invalidHandle = 11;
  static const int invalidArgument = 12;
  static const int backendPanic = 13;
  static const int invalidState = 16;
  static const int collectionAlreadyOpen = 17;
  static const int collectionLocked = 18;
  static const int collectionOpenFailed = 19;
  static const int packageNotFound = 20;
  static const int packageInvalid = 21;
  static const int importCancelled = 22;
  static const int cardNotFound = 23;
  static const int renderFailed = 24;
  static const int queueEmpty = 25;
  static const int schedulingContextStale = 26;
  static const int answerFailed = 27;
  static const int undoUnavailable = 28;
  static const int ioError = 29;
  static const int collectionCorrupt = 30;
  static const int contractVersionMismatch = 31;
  static const int internalError = 32;
}

abstract final class OfficialAnkiSpikeOperation {
  static const int openCollection = 2;
  static const int closeCollection = 3;
  static const int checkCollection = 4;
  static const int importPackage = 5;
  static const int latestProgress = 6;
  static const int cancelOperation = 7;
  static const int listDeckTree = 8;
  static const int searchCards = 9;
  static const int renderCard = 10;
  static const int setCurrentDeck = 11;
  static const int getReviewQueue = 12;
  static const int describeNextStates = 13;
  static const int answerCard = 14;
  static const int getUndoStatus = 15;
  static const int undo = 16;
}

enum OfficialAnkiSpikeErrorCode {
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
  queueEmpty,
  schedulingContextStale,
  answerFailed,
  undoUnavailable,
  ioError,
  collectionCorrupt,
  contractVersionMismatch,
  internalError,
  unknown,
}

class OfficialAnkiSpikeError {
  const OfficialAnkiSpikeError({
    required this.code,
    required this.message,
    this.nativeStatus,
  });

  final OfficialAnkiSpikeErrorCode code;
  final String message;
  final int? nativeStatus;

  @override
  String toString() => 'OfficialAnkiSpikeError(${code.name}: $message)';
}

enum OfficialAnkiSpikeCollectionState {
  uninitialized,
  created,
  open,
  closed,
  unknown,
}

class OfficialAnkiSpikeSnapshot {
  const OfficialAnkiSpikeSnapshot({
    required this.libraryLoaded,
    required this.contractVersion,
    required this.backendCommit,
    required this.collectionState,
    required this.lastOperation,
    this.abiVersion,
    this.handle,
    this.lastError,
  });

  final bool libraryLoaded;
  final int? abiVersion;
  final String backendCommit;
  final int contractVersion;
  final OfficialAnkiSpikeCollectionState collectionState;
  final String lastOperation;
  final int? handle;
  final OfficialAnkiSpikeError? lastError;
}

const String kOfficialAnkiSpikeIsolationDir = 'anki-spike';

class OfficialAnkiOpenRequest {
  const OfficialAnkiOpenRequest({
    required this.collectionPath,
    required this.mediaFolder,
    required this.mediaDb,
    this.checkIntegrity = false,
  });

  /// Isolated under `<support>/anki-spike/<run-id>/`. Never a user profile path.
  factory OfficialAnkiOpenRequest.isolated({
    required String supportDirectory,
    required String runId,
    bool checkIntegrity = false,
  }) {
    if (runId.isEmpty ||
        runId.contains('/') ||
        runId.contains('\\') ||
        runId == '.' ||
        runId == '..') {
      throw const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.invalidArgument,
        message: 'spike run id must be a single path segment',
      );
    }
    final root = '$supportDirectory/$kOfficialAnkiSpikeIsolationDir/$runId';
    return OfficialAnkiOpenRequest(
      collectionPath: '$root/collection.anki2',
      mediaFolder: '$root/collection.media',
      mediaDb: '$root/collection.media.db2',
      checkIntegrity: checkIntegrity,
    );
  }

  final String collectionPath;
  final String mediaFolder;
  final String mediaDb;
  final bool checkIntegrity;

  /// Safe label that does not echo the application support directory.
  String get displayRoot {
    const marker = '/$kOfficialAnkiSpikeIsolationDir/';
    final normalized = collectionPath.replaceAll('\\', '/');
    final index = normalized.indexOf(marker);
    if (index < 0) {
      return '$kOfficialAnkiSpikeIsolationDir/<redacted>';
    }
    final rest = normalized.substring(index + 1);
    final slash = rest.lastIndexOf('/');
    return slash <= 0 ? rest : rest.substring(0, slash);
  }

  /// Throws [OfficialAnkiSpikeError] without echoing full paths.
  void validate() {
    if (!_isAbsolute(collectionPath) ||
        !_isAbsolute(mediaFolder) ||
        !_isAbsolute(mediaDb)) {
      throw const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.invalidArgument,
        message: 'collection, media folder, and media db must be absolute paths',
      );
    }
    if (collectionPath == mediaFolder ||
        collectionPath == mediaDb ||
        mediaFolder == mediaDb) {
      throw const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.invalidArgument,
        message: 'collection, media folder, and media db must be distinct',
      );
    }
  }

  Map<String, Object> toJson() => {
        'collection_path': collectionPath,
        'media_folder': mediaFolder,
        'media_db': mediaDb,
        'check_integrity': checkIntegrity,
      };
}

bool _isAbsolute(String path) =>
    path.startsWith('/') || (path.length > 2 && path[1] == ':');

/// Decode a little-endian 64-bit handle. Must not use 32-bit reads.
int decodeTurnaAnkiHandle(Uint8List bytes) {
  if (bytes.length != 8) {
    throw ArgumentError.value(bytes.length, 'bytes.length', 'handle is 8 bytes');
  }
  final data = ByteData.sublistView(bytes);
  return data.getUint64(0, Endian.little);
}

OfficialAnkiSpikeError errorFromNativeStatus(int status) {
  switch (status) {
    case OfficialAnkiSpikeNativeStatus.unimplemented:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.unimplemented,
        message: 'native operation is not implemented in this spike',
        nativeStatus: OfficialAnkiSpikeNativeStatus.unimplemented,
      );
    case OfficialAnkiSpikeNativeStatus.invalidHandle:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.invalidHandle,
        message: 'native handle is invalid or already closed',
        nativeStatus: OfficialAnkiSpikeNativeStatus.invalidHandle,
      );
    case OfficialAnkiSpikeNativeStatus.invalidArgument:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.invalidArgument,
        message: 'native argument was rejected',
        nativeStatus: OfficialAnkiSpikeNativeStatus.invalidArgument,
      );
    case OfficialAnkiSpikeNativeStatus.backendPanic:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.backendPanic,
        message: 'native panic was caught at the FFI boundary',
        nativeStatus: OfficialAnkiSpikeNativeStatus.backendPanic,
      );
    case OfficialAnkiSpikeNativeStatus.invalidState:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.invalidState,
        message: 'engine is not in a state that allows this operation',
        nativeStatus: OfficialAnkiSpikeNativeStatus.invalidState,
      );
    case OfficialAnkiSpikeNativeStatus.collectionAlreadyOpen:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.collectionAlreadyOpen,
        message: 'collection is already open on this engine',
        nativeStatus: OfficialAnkiSpikeNativeStatus.collectionAlreadyOpen,
      );
    case OfficialAnkiSpikeNativeStatus.collectionLocked:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.collectionLocked,
        message: 'collection path is already open on another engine',
        nativeStatus: OfficialAnkiSpikeNativeStatus.collectionLocked,
      );
    case OfficialAnkiSpikeNativeStatus.collectionOpenFailed:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.collectionOpenFailed,
        message: 'official Collection failed to open or close',
        nativeStatus: OfficialAnkiSpikeNativeStatus.collectionOpenFailed,
      );
    case OfficialAnkiSpikeNativeStatus.packageNotFound:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.packageNotFound,
        message: 'package file was not found',
        nativeStatus: OfficialAnkiSpikeNativeStatus.packageNotFound,
      );
    case OfficialAnkiSpikeNativeStatus.packageInvalid:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.packageInvalid,
        message: 'package is not a valid official Anki package',
        nativeStatus: OfficialAnkiSpikeNativeStatus.packageInvalid,
      );
    case OfficialAnkiSpikeNativeStatus.importCancelled:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.importCancelled,
        message: 'import was cancelled',
        nativeStatus: OfficialAnkiSpikeNativeStatus.importCancelled,
      );
    case OfficialAnkiSpikeNativeStatus.cardNotFound:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.cardNotFound,
        message: 'card was not found',
        nativeStatus: OfficialAnkiSpikeNativeStatus.cardNotFound,
      );
    case OfficialAnkiSpikeNativeStatus.renderFailed:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.renderFailed,
        message: 'official render failed',
        nativeStatus: OfficialAnkiSpikeNativeStatus.renderFailed,
      );
    case OfficialAnkiSpikeNativeStatus.queueEmpty:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.queueEmpty,
        message: 'review queue is empty',
        nativeStatus: OfficialAnkiSpikeNativeStatus.queueEmpty,
      );
    case OfficialAnkiSpikeNativeStatus.schedulingContextStale:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.schedulingContextStale,
        message: 'answer token is stale',
        nativeStatus: OfficialAnkiSpikeNativeStatus.schedulingContextStale,
      );
    case OfficialAnkiSpikeNativeStatus.answerFailed:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.answerFailed,
        message: 'official answer failed',
        nativeStatus: OfficialAnkiSpikeNativeStatus.answerFailed,
      );
    case OfficialAnkiSpikeNativeStatus.undoUnavailable:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.undoUnavailable,
        message: 'undo is not available',
        nativeStatus: OfficialAnkiSpikeNativeStatus.undoUnavailable,
      );
    case OfficialAnkiSpikeNativeStatus.ioError:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.ioError,
        message: 'native IO failed',
        nativeStatus: OfficialAnkiSpikeNativeStatus.ioError,
      );
    case OfficialAnkiSpikeNativeStatus.collectionCorrupt:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.collectionCorrupt,
        message: 'collection failed an integrity check',
        nativeStatus: OfficialAnkiSpikeNativeStatus.collectionCorrupt,
      );
    case OfficialAnkiSpikeNativeStatus.contractVersionMismatch:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.contractVersionMismatch,
        message: 'spike contract version mismatch',
        nativeStatus: OfficialAnkiSpikeNativeStatus.contractVersionMismatch,
      );
    case OfficialAnkiSpikeNativeStatus.internalError:
      return const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.internalError,
        message: 'native internal error',
        nativeStatus: OfficialAnkiSpikeNativeStatus.internalError,
      );
    default:
      return OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.unknown,
        message: 'native status $status',
        nativeStatus: status,
      );
  }
}
