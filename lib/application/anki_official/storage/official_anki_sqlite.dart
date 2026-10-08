import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:turna/core/ohos_target.dart';

bool _opened = false;

/// Registers the sqlite3 loader override for this isolate.
///
/// Called from 11 sites across the catalog, the backup services and
/// `locator.dart` (including the background isolate, via `isolateSetup`),
/// because `open.overrideFor` state is per-isolate — hence the idempotent
/// flag, hence the cost of getting the short-circuit order wrong.
void ensureOfficialAnkiSqlite() {
  if (_opened) return;
  // ADR 0050 §4.1: the HarmonyOS short-circuit must precede the flag, or the
  // background isolate's first call would consume it and every later call
  // would return early without registering.
  if (isHarmonyOsTarget) {
    _opened = true;
    // There is no `OperatingSystem.ohos` to register against: the enum in
    // sqlite3 2.9.4 has six members and `os` is a `Platform.is*` chain that
    // yields null when all six are false, which is exactly this platform.
    // `overrideForAll` is the only entry point that does not dispatch by
    // platform — and it is process-global once set, which is exactly why the
    // branch is guarded above rather than merely checking the platform later.
    open.overrideForAll(_openHarmonyOsSqlite);
    return;
  }
  _opened = true;
  if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, () {
      for (final name in const [
        'libsqlite3.so',
        'libsqlite3.so.0',
        '/lib/x86_64-linux-gnu/libsqlite3.so.0',
        '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
      ]) {
        try {
          return DynamicLibrary.open(name);
        } on ArgumentError {
          continue;
        }
      }
      return DynamicLibrary.open('libsqlite3.so');
    });
    return;
  }
  if (Platform.isAndroid) {
    open.overrideFor(OperatingSystem.android, _openAndroidSqlite);
  }
}

DynamicLibrary _openHarmonyOsSqlite() => DynamicLibrary.open('libsqlite3.so');

DynamicLibrary _openAndroidSqlite() {
  for (final name in const ['libsqlite3.so', 'libsqlite3_flutter_libs.so']) {
    try {
      return DynamicLibrary.open(name);
    } on ArgumentError {
      continue;
    }
  }
  return DynamicLibrary.process();
}

/// Reports what the catalog storage layer actually does on this platform.
///
/// ADR 0050 §4.1: on HarmonyOS nothing used to be registered and the lookup
/// fell through to sqlite3's default path, which threw. Read-only and
/// in-memory: it must not touch the real catalog.
String probeOfficialAnkiSqlite() {
  try {
    ensureOfficialAnkiSqlite();
    final db = sqlite3.openInMemory();
    try {
      final version = db.select('SELECT sqlite_version() AS v').first['v'];
      return 'ok sqlite=$version';
    } finally {
      db.dispose();
    }
  } catch (e) {
    return 'throw ${e.runtimeType}: $e';
  }
}