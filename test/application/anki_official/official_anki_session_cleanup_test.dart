import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/engine/official_anki_session_cleanup.dart';

void main() {
  test('resolved Android libraryPath == null is the production so name', () {
    final resolved = resolveOfficialAnkiCleanupLibraryPath(
      requested: null,
      android: true,
    );
    expect(resolved, 'libturna_anki.so');
    expect(
      resolveOfficialAnkiCleanupLibraryPath(
        requested: '/abs/libturna_anki.so',
        android: true,
      ),
      '/abs/libturna_anki.so',
    );
  });

  test('non-zero handle is closed once through the injectable transport', () async {
    final transport = _FakeCleanupTransport();
    final cleanup = OfficialAnkiSessionCleanup(
      firstWait: const Duration(milliseconds: 20),
      secondWait: const Duration(milliseconds: 50),
      closeHandle: ({
        required int handle,
        required String libraryPath,
        bool alreadyClosed = false,
      }) async {
        officialAnkiCloseHandleInCleanupIsolate(
          handle: handle,
          libraryPath: libraryPath,
          alreadyClosed: alreadyClosed,
          openTransport: (_) => transport,
        );
      },
    );
    final report = await cleanup.run(
      graceful: () async {
        throw TimeoutException('worker stuck');
      },
      handle: 42,
      resolvedLibraryPath: 'libturna_anki.so',
      token: OfficialAnkiCloseOwnership(),
    );
    expect(report.resolvedLibraryPath, 'libturna_anki.so');
    expect(report.handleFreed, isTrue);
    expect(report.orphan, isFalse);
    expect(transport.closed, [42]);
    expect(transport.closeAttempts, 1);
  });

  test('already-closed handle is not freed again', () async {
    final transport = _FakeCleanupTransport();
    final cleanup = OfficialAnkiSessionCleanup(
      firstWait: const Duration(milliseconds: 10),
      closeHandle: ({
        required int handle,
        required String libraryPath,
        bool alreadyClosed = false,
      }) async {
        officialAnkiCloseHandleInCleanupIsolate(
          handle: handle,
          libraryPath: libraryPath,
          alreadyClosed: alreadyClosed,
          openTransport: (_) => transport,
        );
      },
    );
    final report = await cleanup.run(
      graceful: () async {
        throw TimeoutException('worker stuck');
      },
      handle: 7,
      resolvedLibraryPath: 'libturna_anki.so',
      token: OfficialAnkiCloseOwnership(),
      alreadyClosed: true,
    );
    expect(report.handleFreed, isTrue);
    expect(transport.closed, isEmpty);
    expect(transport.closeAttempts, 0);
  });

  test('shared ownership token prevents double free on double dispose', () async {
    final transport = _FakeCleanupTransport();
    final token = OfficialAnkiCloseOwnership();
    final cleanup = OfficialAnkiSessionCleanup(
      firstWait: const Duration(milliseconds: 10),
      closeHandle: ({
        required int handle,
        required String libraryPath,
        bool alreadyClosed = false,
      }) async {
        officialAnkiCloseHandleInCleanupIsolate(
          handle: handle,
          libraryPath: libraryPath,
          alreadyClosed: alreadyClosed,
          openTransport: (_) => transport,
        );
      },
    );
    Future<OfficialAnkiCleanupReport> once() {
      return cleanup.run(
        graceful: () async {
          throw TimeoutException('worker stuck');
        },
        handle: 9,
        resolvedLibraryPath: 'libturna_anki.so',
        token: token,
      );
    }

    final reports = await Future.wait([once(), once()]);
    expect(transport.closed, [9]);
    expect(reports.where((r) => r.handleFreed).length, 1);
    expect(token.claimed, isTrue);
  });

  test('second wait timeout records orphan and does not block further', () async {
    final started = DateTime.now();
    final cleanup = OfficialAnkiSessionCleanup(
      firstWait: const Duration(milliseconds: 10),
      secondWait: const Duration(milliseconds: 30),
      closeHandle: ({
        required int handle,
        required String libraryPath,
        bool alreadyClosed = false,
      }) {
        return Future<void>.delayed(const Duration(seconds: 5));
      },
    );
    final report = await cleanup.run(
      graceful: () async {
        throw TimeoutException('worker stuck');
      },
      handle: 99,
      resolvedLibraryPath: 'libturna_anki.so',
      token: OfficialAnkiCloseOwnership(),
    );
    final elapsed = DateTime.now().difference(started);
    expect(report.orphan, isTrue);
    expect(report.handleFreed, isFalse);
    expect(elapsed.inMilliseconds, lessThan(1000));
  });

  test('zero handle skips native close', () async {
    final transport = _FakeCleanupTransport();
    officialAnkiCloseHandleInCleanupIsolate(
      handle: 0,
      libraryPath: 'libturna_anki.so',
      openTransport: (_) => transport,
    );
    expect(transport.closed, isEmpty);
  });
}

class _FakeCleanupTransport implements OfficialAnkiCleanupTransport {
  final closed = <int>[];
  var closeAttempts = 0;

  @override
  String get libraryPath => 'libturna_anki.so';

  @override
  void engineClose(int handle) {
    closeAttempts += 1;
    closed.add(handle);
  }
}
