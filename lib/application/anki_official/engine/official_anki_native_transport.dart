import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';

final class TurnaAnkiBuffer extends Struct {
  external Pointer<Uint8> ptr;

  @UintPtr()
  external int len;
}

final class TurnaAnkiResult extends Struct {
  @Int32()
  external int status;
  external TurnaAnkiBuffer buffer;
}

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();
typedef _EngineNewNative = TurnaAnkiResult Function(
  Pointer<Uint8> config,
  Size configLen,
);
typedef _EngineNewDart = TurnaAnkiResult Function(
  Pointer<Uint8> config,
  int configLen,
);
typedef _EngineCloseNative = TurnaAnkiResult Function(Uint64 handle);
typedef _EngineCloseDart = TurnaAnkiResult Function(int handle);
typedef _BufferFreeNative = Void Function(Pointer<Uint8> ptr, Size len);
typedef _BufferFreeDart = void Function(Pointer<Uint8> ptr, int len);
typedef _CallNative = TurnaAnkiResult Function(
  Uint64 handle,
  Uint32 operation,
  Pointer<Uint8> request,
  Size requestLen,
);
typedef _CallDart = TurnaAnkiResult Function(
  int handle,
  int operation,
  Pointer<Uint8> request,
  int requestLen,
);
typedef _CancelNative = TurnaAnkiResult Function(Uint64 handle);
typedef _CancelDart = TurnaAnkiResult Function(int handle);

/// Process-local owner of `libturna_anki.so` symbols.
class OfficialAnkiNativeTransport {
  OfficialAnkiNativeTransport._(this._lib, this.libraryPath)
      : _abiVersion = _lib.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
          'turna_anki_abi_version',
        ),
        _engineNew = _lib.lookupFunction<_EngineNewNative, _EngineNewDart>(
          'turna_anki_engine_new',
        ),
        _engineClose = _lib.lookupFunction<_EngineCloseNative, _EngineCloseDart>(
          'turna_anki_engine_close',
        ),
        _bufferFree = _lib.lookupFunction<_BufferFreeNative, _BufferFreeDart>(
          'turna_anki_buffer_free',
        ),
        _call = _lib.lookupFunction<_CallNative, _CallDart>('turna_anki_call'),
        _cancel = _lib.lookupFunction<_CancelNative, _CancelDart>(
          'turna_anki_cancel',
        );

  // Retained so the isolate does not drop the only handle to the .so.
  // ignore: unused_field
  final DynamicLibrary _lib;
  final String libraryPath;
  final _AbiVersionDart _abiVersion;
  final _EngineNewDart _engineNew;
  final _EngineCloseDart _engineClose;
  final _BufferFreeDart _bufferFree;
  final _CallDart _call;
  final _CancelDart _cancel;

  static OfficialAnkiNativeTransport open({String? libraryPath}) {
    final resolved = libraryPath ?? resolveOfficialAnkiLibraryPath();
    if (resolved == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.libraryMissing,
        messageKey: 'official_anki.library_missing',
      );
    }
    try {
      return OfficialAnkiNativeTransport._(_openLibrary(resolved), resolved);
    } on ArgumentError catch (error) {
      throw _mapLoadError(error);
    }
  }

  static DynamicLibrary _openLibrary(String resolved) {
    try {
      return DynamicLibrary.open(resolved);
    } on ArgumentError catch (openError) {
      if (Platform.isAndroid) {
        // Some Android loaders resolve bare names only through the process
        // namespace. If the ABI symbol is not there either, the library is
        // genuinely absent — rethrow the ORIGINAL open error so callers see
        // library_missing, not a misleading symbol_missing.
        try {
          final lib = DynamicLibrary.process();
          lib.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
            'turna_anki_abi_version',
          );
          return lib;
        } on ArgumentError {
          throw openError;
        }
      }
      rethrow;
    }
  }

  int abiVersion() => _abiVersion();

  int engineNew() {
    final result = _engineNew(nullptr, 0);
    final bytes = _takeBuffer(result);
    if (result.status != 0) {
      throw OfficialAnkiException(
        code: officialAnkiErrorCodeFromStatus(result.status),
        messageKey: 'official_anki.engine_new_failed',
        debugDetails: 'status=${result.status}',
      );
    }
    if (bytes.length < 8) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.internalError,
        messageKey: 'official_anki.invalid_handle',
      );
    }
    return ByteData.sublistView(bytes).getUint64(0, Endian.little);
  }

  OfficialAnkiEnvelopeResponse call(
    int handle,
    int operationId,
    OfficialAnkiEnvelopeRequest request,
  ) {
    if (request.operation.isEmpty ||
        OfficialAnkiOperation.idFor(request.operation) != operationId) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.operation_mismatch',
      );
    }
    final encoded = Uint8List.fromList(request.encode());
    final result = _withRequest(encoded, (ptr, len) {
      return _call(handle, operationId, ptr, len);
    });
    return _decodeResult(result, request.requestId);
  }

  OfficialAnkiEnvelopeResponse cancel(int handle) {
    final result = _cancel(handle);
    if (result.status != 0) {
      throw OfficialAnkiException(
        code: officialAnkiErrorCodeFromStatus(result.status),
        messageKey: 'official_anki.cancel_failed',
        debugDetails: 'status=${result.status}',
      );
    }
    final bytes = _takeBuffer(result);
    if (bytes.isEmpty) {
      return OfficialAnkiEnvelopeResponse.fromJson({
        'contractVersion': {'major': 1, 'minor': 0},
        'requestId': 'cancel',
        'ok': true,
        'payload': {'cancelling': true},
        'engine': {
          'abiVersion': 1,
          'backendCommit': '',
          'contractMajor': 1,
          'contractMinor': 0,
        },
        'durationMillis': 0,
      });
    }
    return OfficialAnkiEnvelopeResponse.decode(bytes);
  }

  void engineClose(int handle) {
    final result = _engineClose(handle);
    final _ = _takeBuffer(result);
    if (result.status != 0 && result.status != 11) {
      throw OfficialAnkiException(
        code: officialAnkiErrorCodeFromStatus(result.status),
        messageKey: 'official_anki.engine_close_failed',
        debugDetails: 'status=${result.status}',
      );
    }
  }

  OfficialAnkiEnvelopeResponse _decodeResult(
    TurnaAnkiResult result,
    String requestId,
  ) {
    final status = result.status;
    final bytes = _takeBuffer(result);
    if (status != 0) {
      throw OfficialAnkiException(
        code: officialAnkiErrorCodeFromStatus(status),
        messageKey: 'official_anki.transport_error',
        debugDetails: 'status=$status requestId=$requestId',
      );
    }
    if (bytes.isEmpty) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.internalError,
        messageKey: 'official_anki.empty_payload',
        debugDetails: requestId,
      );
    }
    final response = OfficialAnkiEnvelopeResponse.decode(bytes);
    if (response.requestId != requestId) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.internalError,
        messageKey: 'official_anki.request_id_mismatch',
        debugDetails: '${response.requestId} != $requestId',
      );
    }
    return response;
  }

  Uint8List _takeBuffer(TurnaAnkiResult result) {
    final ptr = result.buffer.ptr;
    final len = result.buffer.len;
    if (ptr == nullptr || len == 0) {
      return Uint8List(0);
    }
    final copy = Uint8List.fromList(ptr.asTypedList(len));
    _bufferFree(ptr, len);
    return copy;
  }

  T _withRequest<T>(
    Uint8List request,
    T Function(Pointer<Uint8> ptr, int len) invoke,
  ) {
    if (request.isEmpty) {
      return invoke(nullptr, 0);
    }
    final ptr = calloc<Uint8>(request.length);
    ptr.asTypedList(request.length).setAll(0, request);
    try {
      return invoke(ptr, request.length);
    } finally {
      calloc.free(ptr);
    }
  }
}

String? resolveOfficialAnkiLibraryPath() {
  const defined = String.fromEnvironment('TURNA_ANKI_LIB');
  if (defined.isNotEmpty && File(defined).existsSync()) {
    return defined;
  }
  final env = Platform.environment['TURNA_ANKI_LIB'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) {
    return env;
  }
  if (Platform.isAndroid) {
    return 'libturna_anki.so';
  }
  final cwd = Directory.current.path;
  for (final relative in const [
    'native/turna_anki_core/target/debug/libturna_anki.so',
    'native/turna_anki_core/target/release/libturna_anki.so',
  ]) {
    final candidate = '$cwd/$relative';
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

OfficialAnkiException _mapLoadError(Object error) {
  final text = error.toString();
  if (text.contains('Failed to load dynamic library') ||
      text.contains('not found') ||
      text.contains('dlopen failed')) {
    return OfficialAnkiException(
      code: OfficialAnkiErrorCode.libraryMissing,
      messageKey: 'official_anki.library_missing',
      debugDetails: text,
    );
  }
  if (text.contains('Failed to lookup symbol') ||
      text.contains('undefined symbol')) {
    return OfficialAnkiException(
      code: OfficialAnkiErrorCode.symbolMissing,
      messageKey: 'official_anki.symbol_missing',
      debugDetails: text,
    );
  }
  return OfficialAnkiException(
    code: OfficialAnkiErrorCode.unknown,
    messageKey: 'official_anki.library_open_failed',
    debugDetails: text,
  );
}

/// Numeric status → error code. Mirrors the `STATUS_*` constants in
/// `bridge/src/engine.rs` (10–41, append-only); locked by
/// `official_anki_status_map_test.dart`, which parses the Rust source so the
/// two hand-maintained tables cannot drift apart again.
OfficialAnkiErrorCode officialAnkiErrorCodeFromStatus(int status) {
  switch (status) {
    case 10:
      return OfficialAnkiErrorCode.unimplemented;
    case 11:
      return OfficialAnkiErrorCode.invalidHandle;
    case 12:
      return OfficialAnkiErrorCode.invalidArgument;
    case 13:
      return OfficialAnkiErrorCode.backendPanic;
    case 16:
      return OfficialAnkiErrorCode.invalidState;
    case 17:
      return OfficialAnkiErrorCode.collectionAlreadyOpen;
    case 18:
      return OfficialAnkiErrorCode.collectionLocked;
    case 19:
      return OfficialAnkiErrorCode.collectionOpenFailed;
    case 20:
      return OfficialAnkiErrorCode.packageNotFound;
    case 21:
      return OfficialAnkiErrorCode.packageInvalid;
    case 22:
      return OfficialAnkiErrorCode.importCancelled;
    case 23:
      return OfficialAnkiErrorCode.cardNotFound;
    case 24:
      return OfficialAnkiErrorCode.renderFailed;
    case 25:
      return OfficialAnkiErrorCode.queueEmpty;
    case 26:
      return OfficialAnkiErrorCode.schedulingContextStale;
    case 27:
      return OfficialAnkiErrorCode.answerFailed;
    case 28:
      return OfficialAnkiErrorCode.undoUnavailable;
    case 29:
      return OfficialAnkiErrorCode.ioError;
    case 30:
      return OfficialAnkiErrorCode.collectionCorrupt;
    case 31:
      return OfficialAnkiErrorCode.contractVersionMismatch;
    case 32:
      return OfficialAnkiErrorCode.internalError;
    case 33:
      return OfficialAnkiErrorCode.pageTokenStale;
    case 34:
      return OfficialAnkiErrorCode.typedFieldNotFound;
    case 35:
      return OfficialAnkiErrorCode.typedClozeEmpty;
    case 36:
      return OfficialAnkiErrorCode.projectionSnapshotStale;
    case 37:
      return OfficialAnkiErrorCode.redoUnavailable;
    case 38:
      return OfficialAnkiErrorCode.deckNotFound;
    case 39:
      return OfficialAnkiErrorCode.schedulerBusy;
    case 40:
      return OfficialAnkiErrorCode.schedulerCapabilityMissing;
    case 41:
      return OfficialAnkiErrorCode.answerCommitUnknown;
    default:
      return OfficialAnkiErrorCode.unknown;
  }
}
