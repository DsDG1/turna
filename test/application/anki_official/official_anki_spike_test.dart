import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/spike/official_anki_spike_engine.dart';
import 'package:turna/application/anki_official/spike/official_anki_spike_ffi.dart';
import 'package:turna/application/anki_official/spike/official_anki_spike_models.dart';
import 'package:turna/application/anki_official/spike/official_anki_spike_page.dart';

void main() {
  tearDown(OfficialAnkiSpikeFfi.debugResetCache);

  group('handle decoding', () {
    test('keeps the full 64-bit value', () {
      final bytes = Uint8List(8);
      final data = ByteData.sublistView(bytes);
      data.setUint64(0, 0x100000001, Endian.little);
      expect(decodeTurnaAnkiHandle(bytes), 0x100000001);
    });

    test('rejects the wrong length', () {
      expect(
        () => decodeTurnaAnkiHandle(Uint8List(4)),
        throwsArgumentError,
      );
    });
  });

  group('error mapping', () {
    test('maps native status codes', () {
      expect(
        errorFromNativeStatus(OfficialAnkiSpikeNativeStatus.unimplemented).code,
        OfficialAnkiSpikeErrorCode.unimplemented,
      );
      expect(
        errorFromNativeStatus(OfficialAnkiSpikeNativeStatus.invalidHandle).code,
        OfficialAnkiSpikeErrorCode.invalidHandle,
      );
      expect(
        errorFromNativeStatus(OfficialAnkiSpikeNativeStatus.backendPanic).code,
        OfficialAnkiSpikeErrorCode.backendPanic,
      );
    });

    test('maps missing-library load failures', () {
      final error = mapOfficialAnkiLoadError(
        ArgumentError(
          'Failed to load dynamic library \'libturna_anki.so\': '
          'dlopen failed: library "libturna_anki.so" not found',
        ),
      );
      expect(error.code, OfficialAnkiSpikeErrorCode.libraryMissing);
    });

    test('maps missing-symbol load failures', () {
      final error = mapOfficialAnkiLoadError(
        ArgumentError('Failed to lookup symbol \'turna_anki_abi_version\''),
      );
      expect(error.code, OfficialAnkiSpikeErrorCode.symbolMissing);
    });
  });

  group('FfiOfficialAnkiSpikeEngine', () {
    test('returns unsupportedPlatform off Android', () {
      final snapshot = FfiOfficialAnkiSpikeEngine(isAndroid: false).probe();
      expect(snapshot.libraryLoaded, isFalse);
      expect(snapshot.lastOperation, 'open_library');
      expect(
        snapshot.lastError?.code,
        OfficialAnkiSpikeErrorCode.unsupportedPlatform,
      );
    });

    test('returns libraryMissing when the opener fails', () {
      final snapshot = FfiOfficialAnkiSpikeEngine(
        isAndroid: true,
        openLibrary: (_) {
          throw ArgumentError(
            'Failed to load dynamic library \'libturna_anki.so\': '
            'dlopen failed: library "libturna_anki.so" not found',
          );
        },
      ).probe();
      expect(snapshot.libraryLoaded, isFalse);
      expect(
        snapshot.lastError?.code,
        OfficialAnkiSpikeErrorCode.libraryMissing,
      );
    });
  });

  group('OfficialAnkiSpikePage', () {
    testWidgets('shows a fake engine snapshot without opening a .so',
        (tester) async {
      const snapshot = OfficialAnkiSpikeSnapshot(
        libraryLoaded: true,
        abiVersion: 1,
        backendCommit: kOfficialAnkiBackendCommit,
        contractVersion: kOfficialAnkiSpikeContractVersion,
        collectionState: OfficialAnkiSpikeCollectionState.uninitialized,
        lastOperation: 'engine_close',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OfficialAnkiSpikePage(
            engine: FakeOfficialAnkiSpikeEngine(snapshot),
          ),
        ),
      );
      expect(find.text('library loaded'), findsOneWidget);
      expect(find.text('yes'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(find.text('engine_close'), findsOneWidget);
      expect(find.text('none'), findsOneWidget);
    });

    testWidgets('shows a structured missing-library error', (tester) async {
      const snapshot = OfficialAnkiSpikeSnapshot(
        libraryLoaded: false,
        backendCommit: kOfficialAnkiBackendCommit,
        contractVersion: kOfficialAnkiSpikeContractVersion,
        collectionState: OfficialAnkiSpikeCollectionState.uninitialized,
        lastOperation: 'open_library',
        lastError: OfficialAnkiSpikeError(
          code: OfficialAnkiSpikeErrorCode.libraryMissing,
          message: 'libturna_anki.so was not packaged',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OfficialAnkiSpikePage(
            engine: FakeOfficialAnkiSpikeEngine(snapshot),
          ),
        ),
      );
      expect(find.text('no'), findsOneWidget);
      expect(
        find.textContaining('libraryMissing'),
        findsOneWidget,
      );
    });
  });
}
