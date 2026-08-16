import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/spike/official_anki_spike_engine.dart';
import 'package:turna/application/anki_official/spike/official_anki_spike_ffi.dart';
import 'package:turna/application/anki_official/spike/official_anki_spike_models.dart';
import 'package:turna/application/anki_official/spike/official_anki_spike_page.dart';

void main() {
  tearDown(OfficialAnkiSpikeFfi.debugResetCache);

  test('stable call payloads are contract envelopes', () {
    expect(
      OfficialAnkiSpikeOperation.nameFor(
        OfficialAnkiSpikeOperation.checkCollection,
      ),
      'CHECK_COLLECTION',
    );
    expect(
      OfficialAnkiSpikeOperation.nameFor(
        OfficialAnkiSpikeOperation.closeCollection,
      ),
      'CLOSE_COLLECTION',
    );
  });

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
      expect(
        errorFromNativeStatus(OfficialAnkiSpikeNativeStatus.invalidState).code,
        OfficialAnkiSpikeErrorCode.invalidState,
      );
      expect(
        errorFromNativeStatus(
          OfficialAnkiSpikeNativeStatus.collectionAlreadyOpen,
        ).code,
        OfficialAnkiSpikeErrorCode.collectionAlreadyOpen,
      );
      expect(
        errorFromNativeStatus(
          OfficialAnkiSpikeNativeStatus.collectionLocked,
        ).code,
        OfficialAnkiSpikeErrorCode.collectionLocked,
      );
      expect(
        errorFromNativeStatus(
          OfficialAnkiSpikeNativeStatus.collectionOpenFailed,
        ).code,
        OfficialAnkiSpikeErrorCode.collectionOpenFailed,
      );
      expect(
        errorFromNativeStatus(OfficialAnkiSpikeNativeStatus.packageNotFound)
            .code,
        OfficialAnkiSpikeErrorCode.packageNotFound,
      );
      expect(
        errorFromNativeStatus(OfficialAnkiSpikeNativeStatus.packageInvalid)
            .code,
        OfficialAnkiSpikeErrorCode.packageInvalid,
      );
      expect(
        errorFromNativeStatus(OfficialAnkiSpikeNativeStatus.importCancelled)
            .code,
        OfficialAnkiSpikeErrorCode.importCancelled,
      );
      expect(
        errorFromNativeStatus(
          OfficialAnkiSpikeNativeStatus.schedulingContextStale,
        ).code,
        OfficialAnkiSpikeErrorCode.schedulingContextStale,
      );
      expect(
        errorFromNativeStatus(OfficialAnkiSpikeNativeStatus.undoUnavailable)
            .code,
        OfficialAnkiSpikeErrorCode.undoUnavailable,
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

    test('rejects relative collection paths before opening the library',
        () async {
      final snapshot = await FfiOfficialAnkiSpikeEngine(
        isAndroid: true,
        openLibrary: (_) => throw StateError('library must not be opened'),
      ).probeCollection(
        const OfficialAnkiOpenRequest(
          collectionPath: 'collection.anki2',
          mediaFolder: '/tmp/media',
          mediaDb: '/tmp/media.db2',
        ),
      );
      expect(snapshot.libraryLoaded, isFalse);
      expect(snapshot.lastOperation, 'validate_paths');
      expect(
        snapshot.lastError?.code,
        OfficialAnkiSpikeErrorCode.invalidArgument,
      );
    });

    test('rejects a relative package path before opening the library', () async {
      final snapshot = await FfiOfficialAnkiSpikeEngine(
        isAndroid: true,
        openLibrary: (_) => throw StateError('library must not be opened'),
      ).importPackage(
        collection: OfficialAnkiOpenRequest.isolated(
          supportDirectory: '/tmp/support',
          runId: 'import-1',
        ),
        packagePath: 'relative.apkg',
      );
      expect(snapshot.lastOperation, 'validate_paths');
      expect(
        snapshot.lastError?.code,
        OfficialAnkiSpikeErrorCode.invalidArgument,
      );
    });

    test('rejects overlapping collection and media paths', () async {
      final snapshot = await FfiOfficialAnkiSpikeEngine(isAndroid: false)
          .probeCollection(
        const OfficialAnkiOpenRequest(
          collectionPath: '/tmp/same',
          mediaFolder: '/tmp/same',
          mediaDb: '/tmp/media.db2',
        ),
      );
      expect(
        snapshot.lastError?.code,
        OfficialAnkiSpikeErrorCode.invalidArgument,
      );
      expect(snapshot.lastError?.message, isNot(contains('/tmp/same')));
    });
  });

  group('OfficialAnkiOpenRequest', () {
    test('builds isolated absolute paths under anki-spike', () {
      final request = OfficialAnkiOpenRequest.isolated(
        supportDirectory: '/data/user/0/app/files',
        runId: 'run-1',
      );
      expect(
        request.collectionPath,
        '/data/user/0/app/files/anki-spike/run-1/collection.anki2',
      );
      expect(
        request.mediaFolder,
        '/data/user/0/app/files/anki-spike/run-1/collection.media',
      );
      expect(
        request.mediaDb,
        '/data/user/0/app/files/anki-spike/run-1/collection.media.db2',
      );
      expect(request.displayRoot, 'anki-spike/run-1');
      request.validate();
    });

    test('rejects a run id that could escape the isolation directory', () {
      expect(
        () => OfficialAnkiOpenRequest.isolated(
          supportDirectory: '/tmp/support',
          runId: '../escape',
        ),
        throwsA(
          isA<OfficialAnkiSpikeError>().having(
            (error) => error.code,
            'code',
            OfficialAnkiSpikeErrorCode.invalidArgument,
          ),
        ),
      );
    });
  });

  group('FfiOfficialAnkiSpikeEngine library failures', () {
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
      expect(find.text('license', skipOffstage: false), findsOneWidget);
      expect(
        find.textContaining('AGPL-3.0-or-later', skipOffstage: false),
        findsOneWidget,
      );
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

    testWidgets('probes an isolated Collection path without path_provider',
        (tester) async {
      const abi = OfficialAnkiSpikeSnapshot(
        libraryLoaded: true,
        abiVersion: 1,
        backendCommit: kOfficialAnkiBackendCommit,
        contractVersion: kOfficialAnkiSpikeContractVersion,
        collectionState: OfficialAnkiSpikeCollectionState.uninitialized,
        lastOperation: 'engine_close',
      );
      const collection = OfficialAnkiSpikeSnapshot(
        libraryLoaded: true,
        abiVersion: 1,
        backendCommit: kOfficialAnkiBackendCommit,
        contractVersion: kOfficialAnkiSpikeContractVersion,
        collectionState: OfficialAnkiSpikeCollectionState.closed,
        lastOperation: 'engine_close',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OfficialAnkiSpikePage(
            engine: FakeOfficialAnkiSpikeEngine(
              abi,
              collectionSnapshot: collection,
            ),
            resolveOpenRequest: () async => OfficialAnkiOpenRequest.isolated(
              supportDirectory: '/tmp/support',
              runId: 'widget-run',
            ),
          ),
        ),
      );
      final probe = find.byKey(const Key('official-anki-spike-probe-collection'));
      expect(probe, findsOneWidget);
      await tester.ensureVisible(probe);
      await tester.tap(probe);
      await tester.pump();
      await tester.pumpAndSettle();
      final root = find.text('anki-spike/widget-run', skipOffstage: false);
      await tester.ensureVisible(root);
      expect(root, findsOneWidget);
      expect(
        find.text('collection probe state', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('closed', skipOffstage: false), findsOneWidget);
      expect(
        find.text('collection last error', skipOffstage: false),
        findsOneWidget,
      );
    });
  });

  group('Dart spike contract', () {
    test('does not parse package ZIP/SQLite/protobuf', () {
      final root = Directory('lib/application/anki_official/spike');
      final sources = root
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      expect(sources, isNotEmpty);
      final banned = <String>[
        'package:sqlite3',
        'package:archive',
        'ZipDecoder',
        'anki_proto',
        'package:protobuf',
      ];
      for (final file in sources) {
        final text = file.readAsStringSync();
        for (final needle in banned) {
          expect(
            text.contains(needle),
            isFalse,
            reason: '${file.path} must not contain $needle',
          );
        }
      }
    });
  });
}
