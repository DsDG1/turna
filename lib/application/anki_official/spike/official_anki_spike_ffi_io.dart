// Dart imports:
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

// Project imports:
import 'package:turna/application/anki_official/spike/official_anki_spike_models.dart';

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

/// Opens `libturna_anki.so` once per isolate and keeps it loaded.
class OfficialAnkiSpikeFfi {
  OfficialAnkiSpikeFfi._(this._lib)
      : _abiVersion = _lib
            .lookupFunction<_AbiVersionNative, _AbiVersionDart>(
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
        ) {
    // Fail fast if the call symbol is missing; the operation itself is P0-007+.
    _lib.lookup('turna_anki_call');
  }

  // Retained so the isolate does not drop the only handle to the .so.
  // ignore: unused_field
  final DynamicLibrary _lib;

  final _AbiVersionDart _abiVersion;
  final _EngineNewDart _engineNew;
  final _EngineCloseDart _engineClose;
  final _BufferFreeDart _bufferFree;

  static OfficialAnkiSpikeFfi? _cached;

  static void debugResetCache() {
    _cached = null;
  }

  static OfficialAnkiSpikeFfi open({
    bool? isAndroid,
    OfficialAnkiLibraryOpener? openLibrary,
  }) {
    final android = isAndroid ?? Platform.isAndroid;
    if (!android) {
      throw const OfficialAnkiSpikeError(
        code: OfficialAnkiSpikeErrorCode.unsupportedPlatform,
        message: 'official Anki native core is only loaded on Android',
      );
    }
    if (_cached != null) {
      return _cached!;
    }
    final opener = openLibrary ?? _defaultOpen;
    try {
      final lib = opener('libturna_anki.so');
      _cached = OfficialAnkiSpikeFfi._(lib as DynamicLibrary);
      return _cached!;
    } on OfficialAnkiSpikeError {
      rethrow;
    } on ArgumentError catch (error) {
      throw mapOfficialAnkiLoadError(error);
    } catch (error) {
      throw mapOfficialAnkiLoadError(error);
    }
  }

  static Object _defaultOpen(String name) => DynamicLibrary.open(name);

  Uint8List takeBuffer(Object result) {
    final typed = result as TurnaAnkiResult;
    final ptr = typed.buffer.ptr;
    final len = typed.buffer.len;
    if (ptr == nullptr || len == 0) {
      return Uint8List(0);
    }
    final copy = Uint8List.fromList(ptr.asTypedList(len));
    _bufferFree(ptr, len);
    return copy;
  }

  int readAbiVersion() => _abiVersion();

  Object createEngine() => _engineNew(nullptr, 0);

  Object closeEngine(int handle) => _engineClose(handle);

  int resultStatus(Object result) => (result as TurnaAnkiResult).status;
}

typedef OfficialAnkiLibraryOpener = Object Function(String name);

OfficialAnkiSpikeError mapOfficialAnkiLoadError(Object error) {
  final text = error.toString();
  final missingLibrary = text.contains('Failed to load dynamic library') ||
      text.contains('library "libturna_anki.so" not found') ||
      text.contains('dlopen failed');
  if (missingLibrary) {
    return OfficialAnkiSpikeError(
      code: OfficialAnkiSpikeErrorCode.libraryMissing,
      message: 'libturna_anki.so was not packaged or failed to load: $error',
    );
  }
  if (text.contains('Failed to lookup symbol') ||
      text.contains('undefined symbol')) {
    return OfficialAnkiSpikeError(
      code: OfficialAnkiSpikeErrorCode.symbolMissing,
      message: 'libturna_anki.so is missing a required C ABI symbol: $error',
    );
  }
  return OfficialAnkiSpikeError(
    code: OfficialAnkiSpikeErrorCode.unknown,
    message: 'failed to open official Anki native library: $error',
  );
}
