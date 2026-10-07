import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

bool _opened = false;

void ensureOfficialAnkiSqlite() {
  if (_opened) return;
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

/// Reports what the catalog storage layer actually does on this platform.
///
/// ADR 0050 §4.1: on HarmonyOS `Platform.isLinux` and `Platform.isAndroid`
/// are both false, so [ensureOfficialAnkiSqlite] registers nothing and the
/// lookup falls through to sqlite3's default path, which has no
/// `OperatingSystem.ohos` member to fall through *to*. Whether that throws or
/// silently mis-resolves is a per-platform fact, so it is measured rather
/// than assumed. Read-only and in-memory: it must not touch the real catalog.
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
