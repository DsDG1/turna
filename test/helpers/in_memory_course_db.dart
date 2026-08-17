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

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqlite3/src/ffi/load_library.dart' show OperatingSystem, open;
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_database_seeder.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/data/srs_state_dao.dart';

bool _sqliteOverrideApplied = false;
bool _pathProviderMockApplied = false;

class _TestPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.path;

  @override
  Future<String?> getApplicationSupportPath() async =>
      Directory.systemTemp.path;
}

void ensurePathProviderMockForTest() {
  if (_pathProviderMockApplied) return;
  PathProviderPlatform.instance = _TestPathProvider();
  _pathProviderMockApplied = true;
}

/// Ensures sqlite3 loads on Linux test hosts where the unversioned
/// `libsqlite3.so` is missing. Safe to call multiple times. Also silences
/// Drift's "multiple databases" warning - tests intentionally create a fresh
/// in-memory DB per case (no shared executor, so no real race).
void ensureSqliteLibForTestHost() {
  if (_sqliteOverrideApplied) return;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
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

/// An [SrsStateDao] backed by a fresh empty in-memory [CourseDatabase] (no
/// asset seeding). The DAO retains the DB for its lifetime. Reuse one DAO
/// across provider instances when a test needs SRS state to survive
/// reconstruction (the in-memory DB is shared that way).
SrsStateDao emptySrsStateDao() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();
  final db = CourseDatabase(NativeDatabase.memory());
  return SrsStateDao(db);
}

/// A [ReviewHistoryDao] backed by a fresh empty in-memory [CourseDatabase].
ReviewHistoryDao emptyReviewHistoryDao() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();
  final db = CourseDatabase(NativeDatabase.memory());
  return ReviewHistoryDao(db);
}

/// A fresh empty in-memory [CourseDatabase] (no asset seeding), for tests
/// that need to register a DB singleton in GetIt (e.g. provider-identity
/// tests where lazy DAOs resolve it transitively).
CourseDatabase emptyInMemoryCourseDatabase() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();
  return CourseDatabase(NativeDatabase.memory());
}
