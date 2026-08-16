// Project imports:
import 'package:turna/application/anki_official/spike/official_anki_spike_ffi.dart';
import 'package:turna/application/anki_official/spike/official_anki_spike_models.dart';

/// Probe the official Anki native spike. Tests inject a [FakeOfficialAnkiSpikeEngine]
/// instead of opening the Android `.so`.
abstract class OfficialAnkiSpikeEngine {
  OfficialAnkiSpikeSnapshot probe();
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
    OfficialAnkiSpikeFfi ffi;
    try {
      ffi = OfficialAnkiSpikeFfi.open(
        isAndroid: isAndroid,
        openLibrary: openLibrary,
      );
    } on OfficialAnkiSpikeError catch (error) {
      return OfficialAnkiSpikeSnapshot(
        libraryLoaded: false,
        abiVersion: null,
        backendCommit: kOfficialAnkiBackendCommit,
        contractVersion: kOfficialAnkiSpikeContractVersion,
        collectionState: OfficialAnkiSpikeCollectionState.uninitialized,
        lastOperation: 'open_library',
        lastError: error,
      );
    }

    var lastOperation = 'open_library';
    try {
      lastOperation = 'abi_version';
      final abi = ffi.readAbiVersion();

      lastOperation = 'engine_new';
      final created = ffi.createEngine();
      final createdStatus = ffi.resultStatus(created);
      if (createdStatus != OfficialAnkiSpikeNativeStatus.ok) {
        return _snapshot(
          libraryLoaded: true,
          abiVersion: abi,
          lastOperation: lastOperation,
          error: errorFromNativeStatus(createdStatus),
        );
      }
      final handle = decodeTurnaAnkiHandle(ffi.takeBuffer(created));

      lastOperation = 'engine_close';
      final closed = ffi.closeEngine(handle);
      final closedStatus = ffi.resultStatus(closed);
      if (closedStatus != OfficialAnkiSpikeNativeStatus.ok) {
        return _snapshot(
          libraryLoaded: true,
          abiVersion: abi,
          handle: handle,
          lastOperation: lastOperation,
          error: errorFromNativeStatus(closedStatus),
        );
      }

      return _snapshot(
        libraryLoaded: true,
        abiVersion: abi,
        handle: handle,
        lastOperation: lastOperation,
      );
    } on OfficialAnkiSpikeError catch (error) {
      return _snapshot(
        libraryLoaded: true,
        lastOperation: lastOperation,
        error: error,
      );
    } catch (error) {
      return _snapshot(
        libraryLoaded: true,
        lastOperation: lastOperation,
        error: OfficialAnkiSpikeError(
          code: OfficialAnkiSpikeErrorCode.unknown,
          message: error.toString(),
        ),
      );
    }
  }

  OfficialAnkiSpikeSnapshot _snapshot({
    required bool libraryLoaded,
    required String lastOperation,
    int? abiVersion,
    int? handle,
    OfficialAnkiSpikeError? error,
  }) {
    return OfficialAnkiSpikeSnapshot(
      libraryLoaded: libraryLoaded,
      abiVersion: abiVersion,
      backendCommit: kOfficialAnkiBackendCommit,
      contractVersion: kOfficialAnkiSpikeContractVersion,
      collectionState: OfficialAnkiSpikeCollectionState.uninitialized,
      lastOperation: lastOperation,
      handle: handle,
      lastError: error,
    );
  }
}

class FakeOfficialAnkiSpikeEngine implements OfficialAnkiSpikeEngine {
  FakeOfficialAnkiSpikeEngine(this.snapshot);

  final OfficialAnkiSpikeSnapshot snapshot;

  @override
  OfficialAnkiSpikeSnapshot probe() => snapshot;
}
