// Dart imports:
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

// Project imports:
import 'package:turna/application/anki_official/spike/official_anki_spike_ffi.dart';
import 'package:turna/application/anki_official/spike/official_anki_spike_models.dart';

/// Probe the official Anki native spike. Tests inject a [FakeOfficialAnkiSpikeEngine]
/// instead of opening the Android `.so`.
abstract class OfficialAnkiSpikeEngine {
  OfficialAnkiSpikeSnapshot probe();

  Future<OfficialAnkiSpikeSnapshot> probeCollection(OfficialAnkiOpenRequest request);

  Future<OfficialAnkiSpikeSnapshot> importPackage({
    required OfficialAnkiOpenRequest collection,
    required String packagePath,
  });
}

class FfiOfficialAnkiSpikeEngine implements OfficialAnkiSpikeEngine {
  FfiOfficialAnkiSpikeEngine({
    this.isAndroid,
    this.openLibrary,
  });

  final bool? isAndroid;
  final OfficialAnkiLibraryOpener? openLibrary;

  @override
  OfficialAnkiSpikeSnapshot probe() {
    return _run((ffi) {
      final created = _requireOk(ffi, 'engine_new', ffi.createEngine());
      final handle = decodeTurnaAnkiHandle(ffi.takeBuffer(created));
      _requireOk(ffi, 'engine_close', ffi.closeEngine(handle));
      return _ok(
        ffi: ffi,
        lastOperation: 'engine_close',
        handle: handle,
        state: OfficialAnkiSpikeCollectionState.uninitialized,
      );
    });
  }

  @override
  Future<OfficialAnkiSpikeSnapshot> probeCollection(
    OfficialAnkiOpenRequest request,
  ) async {
    try {
      request.validate();
    } on OfficialAnkiSpikeError catch (error) {
      return OfficialAnkiSpikeSnapshot(
        libraryLoaded: false,
        backendCommit: kOfficialAnkiBackendCommit,
        contractVersion: kOfficialAnkiSpikeContractVersion,
        collectionState: OfficialAnkiSpikeCollectionState.uninitialized,
        lastOperation: 'validate_paths',
        lastError: error,
      );
    }
    return _run((ffi) {
      final created = _requireOk(ffi, 'engine_new', ffi.createEngine());
      final handle = decodeTurnaAnkiHandle(ffi.takeBuffer(created));
      final payload = utf8.encode(jsonEncode(request.toJson()));
      _requireOkAndFree(
        ffi,
        'open_collection',
        ffi.openCollection(handle, payload),
      );
      _requireOkAndFree(
        ffi,
        'check_collection',
        ffi.call(
          handle,
          OfficialAnkiSpikeOperation.checkCollection,
          _envelope(OfficialAnkiSpikeOperation.checkCollectionName),
        ),
      );
      _requireOkAndFree(
        ffi,
        'close_collection',
        ffi.call(
          handle,
          OfficialAnkiSpikeOperation.closeCollection,
          _envelope(OfficialAnkiSpikeOperation.closeCollectionName),
        ),
      );
      _requireOkAndFree(
        ffi,
        'reopen_collection',
        ffi.openCollection(handle, payload),
      );
      _requireOkAndFree(
        ffi,
        'close_collection',
        ffi.call(
          handle,
          OfficialAnkiSpikeOperation.closeCollection,
          _envelope(OfficialAnkiSpikeOperation.closeCollectionName),
        ),
      );
      _requireOkAndFree(ffi, 'engine_close', ffi.closeEngine(handle));
      return _ok(
        ffi: ffi,
        lastOperation: 'engine_close',
        handle: handle,
        state: OfficialAnkiSpikeCollectionState.closed,
      );
    });
  }

  @override
  Future<OfficialAnkiSpikeSnapshot> importPackage({
    required OfficialAnkiOpenRequest collection,
    required String packagePath,
  }) {
    try {
      collection.validate();
      _validatePackagePath(packagePath);
    } on OfficialAnkiSpikeError catch (error) {
      return Future.value(
        OfficialAnkiSpikeSnapshot(
          libraryLoaded: false,
          backendCommit: kOfficialAnkiBackendCommit,
          contractVersion: kOfficialAnkiSpikeContractVersion,
          collectionState: OfficialAnkiSpikeCollectionState.uninitialized,
          lastOperation: 'validate_paths',
          lastError: error,
        ),
      );
    }
    OfficialAnkiSpikeSnapshot runImport() {
      return _run((ffi) {
        final created = _requireOk(ffi, 'engine_new', ffi.createEngine());
        final handle = decodeTurnaAnkiHandle(ffi.takeBuffer(created));
        final openPayload = utf8.encode(jsonEncode(collection.toJson()));
        _requireOkAndFree(
          ffi,
          'open_collection',
          ffi.openCollection(handle, openPayload),
        );
        _requireOkAndFree(
          ffi,
          'import_package',
          ffi.call(
            handle,
            OfficialAnkiSpikeOperation.importPackage,
            _envelope(OfficialAnkiSpikeOperation.importPackageName, {
              'package_path': packagePath,
              'with_scheduling': true,
              'with_deck_configs': true,
            }),
          ),
        );
        _requireOkAndFree(
          ffi,
          'close_collection',
          ffi.call(
            handle,
            OfficialAnkiSpikeOperation.closeCollection,
            _envelope(OfficialAnkiSpikeOperation.closeCollectionName),
          ),
        );
        _requireOkAndFree(ffi, 'engine_close', ffi.closeEngine(handle));
        return _ok(
          ffi: ffi,
          lastOperation: 'import_package',
          handle: handle,
          state: OfficialAnkiSpikeCollectionState.closed,
        );
      });
    }

    if (openLibrary != null) {
      return Future<OfficialAnkiSpikeSnapshot>.value(runImport());
    }
    final android = isAndroid;
    return Isolate.run(() {
      return FfiOfficialAnkiSpikeEngine(isAndroid: android).importOnThisIsolate(
        collection: collection,
        packagePath: packagePath,
      );
    });
  }

  OfficialAnkiSpikeSnapshot importOnThisIsolate({
    required OfficialAnkiOpenRequest collection,
    required String packagePath,
  }) {
    return _run((ffi) {
      final created = _requireOk(ffi, 'engine_new', ffi.createEngine());
      final handle = decodeTurnaAnkiHandle(ffi.takeBuffer(created));
      final openPayload = utf8.encode(jsonEncode(collection.toJson()));
      _requireOkAndFree(
        ffi,
        'open_collection',
        ffi.openCollection(handle, openPayload),
      );
      _requireOkAndFree(
        ffi,
        'import_package',
        ffi.call(
          handle,
          OfficialAnkiSpikeOperation.importPackage,
          _envelope(OfficialAnkiSpikeOperation.importPackageName, {
            'package_path': packagePath,
            'with_scheduling': true,
            'with_deck_configs': true,
          }),
        ),
      );
      _requireOkAndFree(
        ffi,
        'close_collection',
        ffi.call(
          handle,
          OfficialAnkiSpikeOperation.closeCollection,
          _envelope(OfficialAnkiSpikeOperation.closeCollectionName),
        ),
      );
      _requireOkAndFree(ffi, 'engine_close', ffi.closeEngine(handle));
      return _ok(
        ffi: ffi,
        lastOperation: 'import_package',
        handle: handle,
        state: OfficialAnkiSpikeCollectionState.closed,
      );
    });
  }

  OfficialAnkiSpikeSnapshot _run(
    OfficialAnkiSpikeSnapshot Function(OfficialAnkiSpikeFfi ffi) body,
  ) {
    OfficialAnkiSpikeFfi ffi;
    try {
      ffi = OfficialAnkiSpikeFfi.open(
        isAndroid: isAndroid,
        openLibrary: openLibrary,
      );
    } on OfficialAnkiSpikeError catch (error) {
      return OfficialAnkiSpikeSnapshot(
        libraryLoaded: false,
        backendCommit: kOfficialAnkiBackendCommit,
        contractVersion: kOfficialAnkiSpikeContractVersion,
        collectionState: OfficialAnkiSpikeCollectionState.uninitialized,
        lastOperation: 'open_library',
        lastError: error,
      );
    }

    try {
      final abi = ffi.readAbiVersion();
      final snapshot = body(ffi);
      return OfficialAnkiSpikeSnapshot(
        libraryLoaded: snapshot.libraryLoaded,
        abiVersion: abi,
        backendCommit: snapshot.backendCommit,
        contractVersion: snapshot.contractVersion,
        collectionState: snapshot.collectionState,
        lastOperation: snapshot.lastOperation,
        handle: snapshot.handle,
        lastError: snapshot.lastError,
      );
    } on OfficialAnkiSpikeError catch (error) {
      return OfficialAnkiSpikeSnapshot(
        libraryLoaded: true,
        abiVersion: ffi.readAbiVersion(),
        backendCommit: kOfficialAnkiBackendCommit,
        contractVersion: kOfficialAnkiSpikeContractVersion,
        collectionState: OfficialAnkiSpikeCollectionState.unknown,
        lastOperation: error.message,
        lastError: error,
      );
    } catch (error) {
      return OfficialAnkiSpikeSnapshot(
        libraryLoaded: true,
        backendCommit: kOfficialAnkiBackendCommit,
        contractVersion: kOfficialAnkiSpikeContractVersion,
        collectionState: OfficialAnkiSpikeCollectionState.unknown,
        lastOperation: 'unknown',
        lastError: OfficialAnkiSpikeError(
          code: OfficialAnkiSpikeErrorCode.unknown,
          message: error.toString(),
        ),
      );
    }
  }

  Object _requireOk(OfficialAnkiSpikeFfi ffi, String operation, Object result) {
    final status = ffi.resultStatus(result);
    if (status != OfficialAnkiSpikeNativeStatus.ok) {
      final mapped = errorFromNativeStatus(status);
      throw OfficialAnkiSpikeError(
        code: mapped.code,
        message: operation,
        nativeStatus: status,
      );
    }
    return result;
  }

  /// Native success payloads own a heap buffer. Always copy/free it.
  void _requireOkAndFree(
    OfficialAnkiSpikeFfi ffi,
    String operation,
    Object result,
  ) {
    var taken = false;
    try {
      _requireOk(ffi, operation, result);
      final bytes = ffi.takeBuffer(result);
      taken = true;
      if (bytes.isEmpty) {
        return;
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map && decoded['ok'] == false) {
        final error = decoded['error'];
        final code = error is Map ? error['code']?.toString() : null;
        throw OfficialAnkiSpikeError(
          code: OfficialAnkiSpikeErrorCode.invalidArgument,
          message: '$operation envelope ${code ?? "not_ok"}',
        );
      }
    } finally {
      if (!taken) {
        ffi.takeBuffer(result);
      }
    }
  }

  OfficialAnkiSpikeSnapshot _ok({
    required OfficialAnkiSpikeFfi ffi,
    required String lastOperation,
    required int handle,
    required OfficialAnkiSpikeCollectionState state,
  }) {
    return OfficialAnkiSpikeSnapshot(
      libraryLoaded: true,
      abiVersion: ffi.readAbiVersion(),
      backendCommit: kOfficialAnkiBackendCommit,
      contractVersion: kOfficialAnkiSpikeContractVersion,
      collectionState: state,
      lastOperation: lastOperation,
      handle: handle,
    );
  }
}

class FakeOfficialAnkiSpikeEngine implements OfficialAnkiSpikeEngine {
  FakeOfficialAnkiSpikeEngine(
    this.snapshot, {
    this.collectionSnapshot,
  });

  final OfficialAnkiSpikeSnapshot snapshot;
  final OfficialAnkiSpikeSnapshot? collectionSnapshot;

  @override
  OfficialAnkiSpikeSnapshot probe() => snapshot;

  @override
  Future<OfficialAnkiSpikeSnapshot> probeCollection(
    OfficialAnkiOpenRequest request,
  ) async {
    request.validate();
    return collectionSnapshot ?? snapshot;
  }

  @override
  Future<OfficialAnkiSpikeSnapshot> importPackage({
    required OfficialAnkiOpenRequest collection,
    required String packagePath,
  }) async {
    collection.validate();
    _validatePackagePath(packagePath);
    return collectionSnapshot ?? snapshot;
  }
}

Uint8List _envelope(String operation, [Map<String, Object?>? payload]) {
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'contractVersion': <String, int>{'major': 1, 'minor': 0},
        'requestId': 'spike-$operation',
        'operation': operation,
        'payload': payload ?? const <String, Object?>{},
      }),
    ),
  );
}

void _validatePackagePath(String packagePath) {
  final absolute = packagePath.startsWith('/') ||
      (packagePath.length > 2 && packagePath[1] == ':');
  if (!absolute) {
    throw const OfficialAnkiSpikeError(
      code: OfficialAnkiSpikeErrorCode.invalidArgument,
      message: 'package path must be absolute',
    );
  }
}
