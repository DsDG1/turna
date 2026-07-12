// Test helper: build an in-memory [CourseDatabase] seeded from the bundled
// JSON assets, for use in unit tests that exercise the DB-backed course
// loader without touching the device filesystem.
//
// On Linux test hosts the `sqlite3` Dart package looks for the unversioned
// `libsqlite3.so`, which is typically only present if `libsqlite3-dev` is
// installed. The versioned `libsqlite3.so.0` ships with the base OS, so we
// override the loader to use it when running tests. On real devices
// `sqlite3_flutter_libs` bundles the native library, so this override is
// test-host only.

import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/src/ffi/load_library.dart' show OperatingSystem, open;
import 'package:varnamala/courses/course_loader.dart';
import 'package:varnamala/data/course_database.dart';
import 'package:varnamala/data/course_database_seeder.dart';

bool _sqliteOverrideApplied = false;

/// Ensures sqlite3 loads on Linux test hosts where the unversioned
/// `libsqlite3.so` is missing. Safe to call multiple times.
void ensureSqliteLibForTestHost() {
  if (_sqliteOverrideApplied) return;
  if (!Platform.isLinux) {
    _sqliteOverrideApplied = true;
    return;
  }
  // Try the versioned system library if the unversioned soname is missing.
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } on ArgumentError {
      return DynamicLibrary.open('libsqlite3.so.0');
    }
  });
  _sqliteOverrideApplied = true;
}

/// Creates an in-memory [CourseDatabase], seeds it from the bundled Turkish
/// JSON assets, and injects it into [CourseLoader] via [overrideDatabase] so
/// the static loader resolves to this DB. Returns the DB for direct queries.
Future<CourseDatabase> seedInMemoryCourseDb() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();
  final db = CourseDatabase(NativeDatabase.memory());
  await DatabaseSeeder(db).seedIfNeeded();
  CourseLoader.overrideDatabase(() => db);
  return db;
}