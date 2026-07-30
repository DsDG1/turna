// Bridges HarmonyOS native RDB (@kit.ArkData relationalStore) to Flutter drift
// via MethodChannel. Used as a drop-in replacement for NativeDatabase on OHos.
//
// Usage:
// ```dart
// if (defaultTargetPlatform == TargetPlatform.ohos) {
//   final executor = HarmonyOsRdbExecutor('course.db');
//   final db = CourseDatabase(executor);
//   await executor.ensureOpen(db);
//   return db;
// }
// ```

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/src/runtime/executor/executor.dart'
    show ArgumentsForBatchedStatement, TransactionExecutor;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// A drift [QueryExecutor] backed by HarmonyOS RDB via MethodChannel.
///
/// All SQL statements are passed as strings with positional `?` parameters.
/// The bridge serializes parameters to JSON and deserializes ResultSet rows
/// back to `Map<String, Object?>`.
///
/// **Limitations vs NativeDatabase:**
/// - `runInsert` returns 0 (HarmonyOS RDB does not expose lastInsertRowId).
///   This is acceptable because all project tables use TEXT primary keys.
/// - `runUpdate`/`runDelete` return 0 (affected rows not exposed).
/// - BLOB columns return null (project has no BLOB columns).
/// - Transaction support is best-effort (each executeSql is atomic).
class HarmonyOsRdbExecutor extends QueryExecutor implements TransactionExecutor {
  static const MethodChannel _channel = MethodChannel('com.varnamala/rdb');

  @override
  final SqlDialect dialect = SqlDialect.sqlite;

  final String dbName;
  bool _isOpen = false;

  HarmonyOsRdbExecutor(this.dbName);

  @override
  bool get supportsNestedTransactions => false;

  @override
  Future<void> send() async {}

  @override
  Future<void> rollback() async {}

  @override
  bool get isOpen => _isOpen;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async {
    if (_isOpen) return true;
    final ok = await _channel.invokeMethod<bool>('openDb', dbName);
    if (ok != true) {
      throw Exception('Failed to open HarmonyOS RDB: $dbName');
    }

    // Create tables if database is new
    final oldVersionRows = await runSelect('PRAGMA user_version', const []);
    final oldVersionValue = oldVersionRows.isEmpty
        ? 0
        : oldVersionRows.first.values.first;
    final oldVersion = oldVersionValue is int
        ? oldVersionValue
        : int.tryParse('$oldVersionValue') ?? 0;

    if (oldVersion == 0) {
      // Create all tables for CourseDatabase schema version 6
      await _createTables();
    }

    // Set schema version
    if (oldVersion != user.schemaVersion) {
      await runCustom('PRAGMA user_version = ${user.schemaVersion}');
    }

    _isOpen = true;
    return true;
  }

  /// Create all tables for the course database schema.
  Future<void> _createTables() async {
    // sections table
    await runCustom('''
      CREATE TABLE IF NOT EXISTS sections (
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        level TEXT NOT NULL DEFAULT '',
        prerequisite_section_ids TEXT NOT NULL DEFAULT '[]',
        sort_order INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(id)
      )
    ''');

    // units table
    await runCustom('''
      CREATE TABLE IF NOT EXISTS units (
        id TEXT NOT NULL,
        section_id TEXT NOT NULL REFERENCES sections(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        prerequisite_unit_ids TEXT NOT NULL DEFAULT '[]',
        sort_order INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(id)
      )
    ''');

    // lessons table
    await runCustom('''
      CREATE TABLE IF NOT EXISTS lessons (
        id TEXT NOT NULL,
        unit_id TEXT NOT NULL REFERENCES units(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'normal',
        template TEXT NOT NULL DEFAULT 'legacy',
        prerequisite_lesson_ids TEXT NOT NULL DEFAULT '[]',
        sort_order INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(id)
      )
    ''');

    // lesson_contents table
    await runCustom('''
      CREATE TABLE IF NOT EXISTS lesson_contents (
        lesson_id TEXT NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
        content_json TEXT NOT NULL,
        PRIMARY KEY(lesson_id)
      )
    ''');

    // vocabulary table
    await runCustom('''
      CREATE TABLE IF NOT EXISTS vocabulary (
        id TEXT NOT NULL,
        term TEXT NOT NULL,
        translation TEXT NOT NULL,
        pronunciation TEXT,
        audio_asset TEXT,
        tags TEXT NOT NULL DEFAULT '[]',
        PRIMARY KEY(id)
      )
    ''');

    // grammar_points table
    await runCustom('''
      CREATE TABLE IF NOT EXISTS grammar_points (
        id TEXT NOT NULL,
        title TEXT NOT NULL,
        explanation TEXT NOT NULL DEFAULT '',
        example_expression_ids TEXT NOT NULL DEFAULT '[]',
        example_sentence_ids TEXT NOT NULL DEFAULT '[]',
        practice_items TEXT NOT NULL DEFAULT '[]',
        PRIMARY KEY(id)
      )
    ''');

    // course_meta table
    await runCustom('''
      CREATE TABLE IF NOT EXISTS course_meta (
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        PRIMARY KEY(key)
      )
    ''');

    // expressions table
    await runCustom('''
      CREATE TABLE IF NOT EXISTS expressions (
        id TEXT NOT NULL,
        term TEXT NOT NULL,
        translation TEXT NOT NULL,
        pronunciation TEXT,
        audio_asset TEXT,
        tags TEXT NOT NULL DEFAULT '[]',
        PRIMARY KEY(id)
      )
    ''');

    // anki_imports table
    await runCustom('''
      CREATE TABLE IF NOT EXISTS anki_imports (
        import_id TEXT NOT NULL,
        source_path TEXT NOT NULL,
        source_hash TEXT NOT NULL,
        imported_at INTEGER NOT NULL,
        deck_count INTEGER NOT NULL DEFAULT 0,
        note_count INTEGER NOT NULL DEFAULT 0,
        card_count INTEGER NOT NULL DEFAULT 0,
        media_count INTEGER NOT NULL DEFAULT 0,
        notetypes_json TEXT NOT NULL DEFAULT '{}',
        ai_enhanced INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY(import_id)
      )
    ''');

    // srs_states table (v7) - one row per tracked SRS item
    await runCustom('''
      CREATE TABLE IF NOT EXISTS srs_states (
        word_id TEXT NOT NULL,
        queue TEXT NOT NULL,
        due_at INTEGER NOT NULL,
        interval_days INTEGER NOT NULL DEFAULT 1,
        ease REAL NOT NULL DEFAULT 2.5,
        reps INTEGER NOT NULL DEFAULT 0,
        lapses INTEGER NOT NULL DEFAULT 0,
        is_leech INTEGER NOT NULL DEFAULT 0,
        type TEXT NOT NULL DEFAULT 'word',
        last_reviewed_at INTEGER,
        stability REAL,
        difficulty REAL,
        fsrs_state INTEGER NOT NULL DEFAULT 1,
        learning_step INTEGER,
        PRIMARY KEY(word_id)
      )
    ''');

    // review_events table (v7) - one row per SRS review
    await runCustom('''
      CREATE TABLE IF NOT EXISTS review_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id TEXT NOT NULL,
        queue TEXT NOT NULL,
        reviewed_at INTEGER NOT NULL,
        quality INTEGER NOT NULL,
        prev_interval_days INTEGER NOT NULL,
        next_interval_days INTEGER NOT NULL,
        prev_ease REAL NOT NULL,
        next_ease REAL NOT NULL,
        reps INTEGER NOT NULL,
        lapses INTEGER NOT NULL,
        type TEXT NOT NULL DEFAULT 'word'
      )
    ''');

    // Indexes for review_events
    await runCustom(
        'CREATE INDEX IF NOT EXISTS review_events_card_idx ON review_events (card_id)');
    await runCustom(
        'CREATE INDEX IF NOT EXISTS review_events_time_idx ON review_events (reviewed_at)');
  }

  @override
  Future<int> runInsert(String sql, List<Object?> args) async {
    await _execute(sql, args);
    // HarmonyOS RDB executeSql does not return lastInsertRowId.
    // All project tables use TEXT primary keys (no AUTOINCREMENT),
    // so returning 0 is safe.
    return 0;
  }

  @override
  Future<int> runUpdate(String sql, List<Object?> args) async {
    await _execute(sql, args);
    return 0;
  }

  @override
  Future<int> runDelete(String sql, List<Object?> args) async {
    await _execute(sql, args);
    return 0;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String sql,
    List<Object?> args,
  ) async {
    final rows = await _channel.invokeMethod<List<dynamic>?>(
      'query',
      _toArgsMap(sql, args),
    );
    if (rows == null) return const [];
    return rows
        .cast<Map>()
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList();
  }

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    for (final argSet in statements.arguments) {
      final sql = statements.statements[argSet.statementIndex];
      await _execute(sql, argSet.arguments);
    }
  }

  @override
  TransactionExecutor beginTransaction() {
    // HarmonyOS RDB does not support nested transactions and auto-commits each
    // executeSql. Return `this` so statements inside a drift `transaction`
    // callback are executed against the real store instead of being swallowed
    // by a no-op executor.
    return this;
  }

  @override
  QueryExecutor beginExclusive() => this;

  @override
  Future<void> runCustom(String sql, [List<Object?>? args]) async {
    // DDL statements (CREATE TABLE, ALTER TABLE, etc.) and transaction control
    // (BEGIN, COMMIT, ROLLBACK) all go through executeSql.
    await _execute(sql, args);
  }

  @override
  Future<void> close() async {
    await _channel.invokeMethod<void>('close');
    _isOpen = false;
  }

  // --- helpers ---

  Future<void> _execute(String sql, List<Object?>? args) async {
    debugPrint('🔧 SQL: $sql');
    debugPrint('🔧 Params: ${args ?? const []}');
    final result = await _channel.invokeMethod<bool>(
      'executeSql',
      _toArgsMap(sql, args ?? const []),
    );
    if (result != true) {
      throw StateError('RDB execute failed: $sql');
    }
  }

  Map<String, dynamic> _toArgsMap(String sql, List<Object?> args) {
    return {
      'sql': sql,
      'params': args.map<dynamic>(_serializeParam).toList(),
    };
  }

  /// Serialize a Dart parameter for the MethodChannel.
  /// HarmonyOS RDB supports: INTEGER (int), FLOAT (double), STRING (string),
  /// and NULL. Booleans are serialized as integers (0/1).
  dynamic _serializeParam(Object? value) {
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value;
    if (value is double) return value;
    if (value is String) return value;
    // Fallback: convert to string (for JSON-encoded fields like tags arrays)
    return value.toString();
  }
}
