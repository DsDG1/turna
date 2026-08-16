// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:turna/application/anki_official/spike/official_anki_spike_ffi.dart';
import 'package:turna/application/anki_official/spike/official_anki_spike_models.dart';

/// Probe the official Anki native spike. Tests inject a [FakeOfficialAnkiSpikeEngine]
/// instead of opening the Android `.so`.
abstract class OfficialAnkiSpikeEngine {
  OfficialAnkiSpikeSnapshot probe();

  Future<OfficialAnkiSpikeSnapshot> probeCollection(OfficialAnkiOpenRequest request);
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
        ffi.call(handle, OfficialAnkiSpikeOperation.checkCollection),
      );
      _requireOkAndFree(
        ffi,
        'close_collection',
        ffi.call(handle, OfficialAnkiSpikeOperation.closeCollection),
      );
      _requireOkAndFree(
        ffi,
        'reopen_collection',
        ffi.openCollection(handle, payload),
      );
      _requireOkAndFree(
        ffi,
        'close_collection',
        ffi.call(handle, OfficialAnkiSpikeOperation.closeCollection),
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
    try {
      _requireOk(ffi, operation, result);
    } finally {
      ffi.takeBuffer(result);
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
}
