import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';

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
