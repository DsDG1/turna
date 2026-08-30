import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:turna/application/anki_official/engine/official_anki_native_transport.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Shared close-ownership token for graceful dispose and timeout cleanup.
class OfficialAnkiCloseOwnership {
  var _claimed = false;

  bool get claimed => _claimed;

  bool tryClaim() {
    if (_claimed) return false;
    _claimed = true;
    return true;
  }
}

class OfficialAnkiCleanupReport {
  const OfficialAnkiCleanupReport({
    required this.orphan,
    required this.resolvedLibraryPath,
    required this.handleFreed,
    this.closeAttempts = 0,
  });

  final bool orphan;
  final String? resolvedLibraryPath;
  final bool handleFreed;
  final int closeAttempts;
}

/// Opens a transport used only by cleanup. Tests inject a fake.
typedef OfficialAnkiCleanupTransportFactory = OfficialAnkiCleanupTransport
    Function(String libraryPath);

abstract class OfficialAnkiCleanupTransport {
  void engineClose(int handle);
  String get libraryPath;
}

class _NativeCleanupTransport implements OfficialAnkiCleanupTransport {
  _NativeCleanupTransport(this._inner);

  final OfficialAnkiNativeTransport _inner;

  @override
  String get libraryPath => _inner.libraryPath;

  @override
  void engineClose(int handle) => _inner.engineClose(handle);
}

OfficialAnkiCleanupTransport officialAnkiOpenCleanupTransport(String libraryPath) {
  return _NativeCleanupTransport(
    OfficialAnkiNativeTransport.open(libraryPath: libraryPath),
  );
}

/// Resolves the production native path. Android `libraryPath == null` becomes
/// `libturna_anki.so` — the packaged jniLibs name.
String? resolveOfficialAnkiCleanupLibraryPath({
  String? requested,
  bool? android,
}) {
  if (requested != null && requested.isNotEmpty) {
    return requested;
  }
  final isAndroid = android ?? Platform.isAndroid;
  if (isAndroid) {
    return 'libturna_anki.so';
  }
  return resolveOfficialAnkiLibraryPath();
}

/// Closes a native engine handle on a dedicated isolate.
///
/// The UI isolate must not call [OfficialAnkiNativeTransport.engineClose]
/// after a dispose timeout — that FFI lock can stall the reviewer.
Future<void> officialAnkiCloseHandleOffUiIsolate({
  required int handle,
  required String libraryPath,
  OfficialAnkiCleanupTransportFactory? openTransport,
  bool alreadyClosed = false,
}) {
  if (handle == 0 || alreadyClosed) {
    return Future<void>.value();
  }
  if (openTransport != null) {
    officialAnkiCloseHandleInCleanupIsolate(
      handle: handle,
      libraryPath: libraryPath,
      openTransport: openTransport,
      alreadyClosed: alreadyClosed,
    );
    return Future<void>.value();
  }
  return Isolate.run(() {
    officialAnkiCloseHandleInCleanupIsolate(
      handle: handle,
      libraryPath: libraryPath,
    );
  });
}

void officialAnkiCloseHandleInCleanupIsolate({
  required int handle,
  required String libraryPath,
  OfficialAnkiCleanupTransportFactory? openTransport,
  bool alreadyClosed = false,
}) {
  if (handle == 0 || alreadyClosed) return;
  final factory = openTransport ?? officialAnkiOpenCleanupTransport;
  final transport = factory(libraryPath);
  transport.engineClose(handle);
}

typedef OfficialAnkiCloseHandle = Future<void> Function({
  required int handle,
  required String libraryPath,
  bool alreadyClosed,
});

/// Bounded two-layer cleanup. The caller Future completes after the second
/// wait; a still-running close is recorded as orphan and does not block again.
class OfficialAnkiSessionCleanup {
  OfficialAnkiSessionCleanup({
    OfficialAnkiCloseHandle? closeHandle,
    this.firstWait = const Duration(seconds: 8),
    this.secondWait = const Duration(seconds: 2),
  }) : closeHandle = closeHandle ??
            (({
              required int handle,
              required String libraryPath,
              bool alreadyClosed = false,
            }) {
              return officialAnkiCloseHandleOffUiIsolate(
                handle: handle,
                libraryPath: libraryPath,
                alreadyClosed: alreadyClosed,
              );
            });

  final OfficialAnkiCloseHandle closeHandle;
  final Duration firstWait;
  final Duration secondWait;

  Future<OfficialAnkiCleanupReport> run({
    required Future<void> Function() graceful,
    required int handle,
    required String? resolvedLibraryPath,
    required OfficialAnkiCloseOwnership token,
    bool alreadyClosed = false,
  }) async {
    var orphan = false;
    var closeAttempts = 0;
    try {
      await graceful().timeout(firstWait);
      token.tryClaim();
      return OfficialAnkiCleanupReport(
        orphan: false,
        resolvedLibraryPath: resolvedLibraryPath,
        handleFreed: alreadyClosed || handle == 0 || token.claimed,
        closeAttempts: 0,
      );
    } catch (suppressed) {
      debugPrint('[OfficialAnkiSessionCleanup] [OfficialAnkiSessionCleanup] cleanup step suppressed: $suppressed');
      orphan = true;
    }
    final library = resolvedLibraryPath;
    if (alreadyClosed ||
        handle == 0 ||
        library == null ||
        library.isEmpty ||
        !token.tryClaim()) {
      return OfficialAnkiCleanupReport(
        orphan: orphan,
        resolvedLibraryPath: library,
        handleFreed: alreadyClosed,
        closeAttempts: 0,
      );
    }
    closeAttempts = 1;
    try {
      await closeHandle(
        handle: handle,
        libraryPath: library,
        alreadyClosed: alreadyClosed,
      ).timeout(secondWait);
      orphan = false;
    } on TimeoutException {
      orphan = true;
    } catch (suppressed) {
      debugPrint('[OfficialAnkiSessionCleanup] [OfficialAnkiSessionCleanup] cleanup step suppressed: $suppressed');
      orphan = true;
    }
    return OfficialAnkiCleanupReport(
      orphan: orphan,
      resolvedLibraryPath: library,
      handleFreed: !orphan,
      closeAttempts: closeAttempts,
    );
  }
}
