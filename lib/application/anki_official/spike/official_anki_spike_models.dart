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
}

enum OfficialAnkiSpikeErrorCode {
  unsupportedPlatform,
  libraryMissing,
  symbolMissing,
  invalidHandle,
  unimplemented,
  backendPanic,
  invalidArgument,
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
    default:
      return OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.unknown,
        message: 'native status $status',
        nativeStatus: status,
      );
  }
}
