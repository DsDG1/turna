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
}

abstract final class OfficialAnkiSpikeOperation {
  static const int openCollection = 2;
  static const int closeCollection = 3;
  static const int checkCollection = 4;
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
    default:
      return OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.unknown,
        message: 'native status $status',
        nativeStatus: status,
      );
  }
}
