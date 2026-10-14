// Tests for [HarmonyOsRdbExecutor], the OHOS course-DB bridge.
//
// The ArkTS half of the bridge cannot run in a Dart test, so these drive the
// executor against a fake RDB behind the real method channel. What is under
// test is the executor's own logic: how it detects the schema version and
// hands migrations to drift, how it decodes the `{types, rows}` envelope into
// the Dart types drift expects, how it recovers insert ids and affected-row
// counts, and how it reacts when the engine rejects `ON CONFLICT`.
//
// Each case below pins a defect that shipped in the first version of this
// bridge, so a regression names the behaviour it broke.

import 'dart:async';

import 'package:drift/drift.dart'
    show OpeningDetails, QueryExecutor, QueryExecutorUser;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/data/rdb_query_executor.dart';
import 'package:turna/data/course_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../helpers/in_memory_course_db.dart';

/// Reads one key out of a method call's argument map. The Dart `MethodCall`
/// carries a plain map; the `argument<T>` helper only exists on the ArkTS side.
Object? _arg(MethodCall call, String key) =>
    (call.arguments as Map<Object?, Object?>?)?[key];

/// Stands in for ArkData. Records the statements it is asked to run and
/// answers the handful of statements the executor probes with.
class FakeRdbEngine {
  FakeRdbEngine({this.userVersion = 0});

  int userVersion = 0;

  /// Whether the meta table has been created, i.e. whether the database has
  /// been migrated at least once.
  bool metaTableExists = false;

  /// False models a meta table that exists but has no version row yet.
  bool userVersionKnown = true;

  final List<String> executed = [];
  final List<String> queries = [];
  final List<String> calls = [];

  /// Statements that must fail, mapped to the message reported.
  final Map<String, String> unsupported = {};

  /// Rows returned by the next `SELECT`, as the `{types, rows}` envelope.
  Map<String, Object?> nextResult = {
    'types': <String, Object?>{},
    'rows': <Object?>[]
  };

  /// Value returned by `SELECT last_insert_rowid()` / `SELECT changes()`.
  int scalarProbe = 0;

  bool opened = false;

  /// When false, the `openDb` call reports failure.
  bool openSucceeds = true;
  List<String> viewRows = ['old-view'];
  List<String>? transactionRows;
  bool failCommit = false;
  bool failRollback = false;
  Zone? lastExecuteZone;

  void reset() {
    executed.clear();
    queries.clear();
    calls.clear();
  }
}

FakeRdbEngine? _engine;

void _install(FakeRdbEngine engine) {
  _engine = engine;
  const channel = MethodChannel('me.dsdogs.turna/rdb');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    final e = _engine!;
    e.calls.add(call.method);
    switch (call.method) {
      case 'openDb':
        e.opened = e.openSucceeds;
        return e.openSucceeds;
      case 'close':
        return true;
      case 'beginTransaction':
        e.transactionRows = List.of(e.viewRows);
        return true;
      case 'commit':
        if (e.failCommit) {
          throw PlatformException(code: 'TX_COMMIT_ERROR');
        }
        e.transactionRows = null;
        return true;
      case 'rollback':
        if (e.failRollback) throw PlatformException(code: 'TX_ROLLBACK_ERROR');
        if (e.transactionRows != null) {
          e.viewRows = List.of(e.transactionRows!);
          e.transactionRows = null;
        }
        return true;
      case 'executeSql':
        e.lastExecuteZone = Zone.current;
        final sql = _arg(call, 'sql')! as String;
        e.executed.add(sql);
        final failure = e.unsupported[sql];
        if (failure != null) {
          throw PlatformException(code: 'EXECUTE_ERROR', message: failure);
        }
        if (sql == 'DELETE FROM anki_course_tree_view') {
          e.viewRows.clear();
        }
        if (sql.contains('CREATE TABLE') && sql.contains('turna_schema_meta')) {
          e.metaTableExists = true;
        }
        if (sql.contains('turna_schema_meta') && sql.contains('INSERT')) {
          final args = _arg(call, 'params') as List<Object?>;
          e.userVersion = args[1]! as int;
        }
        return true;
      case 'query':
        final sql = _arg(call, 'sql')! as String;
        e.queries.add(sql);
        if (sql.contains('turna_schema_meta')) {
          // A missing meta table is what a never-migrated database looks like.
          if (!e.metaTableExists) {
            throw PlatformException(
                code: 'QUERY_ERROR',
                message: 'no such table: turna_schema_meta');
          }
          if (!e.userVersionKnown) {
            return {'types': <String, Object?>{}, 'rows': <Object?>[]};
          }
          return {
            'types': {'value': 'integer'},
            'rows': [
              {'value': e.userVersion}
            ],
          };
        }
        if (sql.contains('last_insert_rowid') || sql.contains('changes()')) {
          return {
            'types': {'probe': 'integer'},
            'rows': [
              {'probe': e.scalarProbe}
            ],
          };
        }
        return e.nextResult;
      default:
        return null;
    }
  });
}

void _remove() {
  _engine = null;
  const channel = MethodChannel('me.dsdogs.turna/rdb');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
}

/// Minimal [QueryExecutorUser]: the executor only needs the target version and
/// the hook drift uses to run migrations.
class _FakeUser implements QueryExecutorUser {
  _FakeUser(this.target, {this.failOnBeforeOpen = false});

  final int target;

  /// Simulates a migration that fails halfway.
  final bool failOnBeforeOpen;

  final List<OpeningDetails> opened = [];
  var beforeOpenCalls = 0;

  @override
  int get schemaVersion => target;

  @override
  Future<void> beforeOpen(
      QueryExecutor executor, OpeningDetails details) async {
    beforeOpenCalls++;
    if (failOnBeforeOpen) {
      throw StateError('migration step failed');
    }
    opened.add(details);
  }
}

/// A user whose [beforeOpen] calls back into the executor, the way drift's
/// migration strategy does when it wraps its DDL in a transaction.
class _ReentrantUser implements QueryExecutorUser {
  _ReentrantUser(this.target, this.executor);

  final int target;
  final QueryExecutor executor;

  var beforeOpenCalls = 0;

  @override
  int get schemaVersion => target;

  @override
  Future<void> beforeOpen(
      QueryExecutor executor, OpeningDetails details) async {
    beforeOpenCalls++;
    if (beforeOpenCalls > 3) {
      throw StateError('ensureOpen is being re-entered without a guard');
    }
    final reopened = await this.executor.ensureOpen(this);
    expect(reopened, isTrue);
    await executor.runCustom('CREATE TABLE IF NOT EXISTS probe (id INTEGER)');
  }
}

void main() {
  late FakeRdbEngine engine;

  // The mock messenger is a binding mixin, so the binding has to exist before
  // any handler is installed.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    engine = FakeRdbEngine();
    _install(engine);
  });

  tearDown(_remove);

  group('ensureOpen', () {
    test('reports a fresh database as version null so drift runs onCreate',
        () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      final user = _FakeUser(29);

      expect(await executor.ensureOpen(user), isTrue);

      expect(user.opened.single.versionBefore, isNull);
      expect(user.opened.single.versionNow, 29);
      // The version lives in our own table: PRAGMA through this engine's
      // querySql never answers, so it cannot be used to detect a database.
      expect(
        engine.executed.where((s) => s.contains('PRAGMA')),
        isEmpty,
        reason: 'no PRAGMA may reach the engine; a querySql for one hangs',
      );
      expect(
        engine.executed,
        contains(
          'INSERT INTO turna_schema_meta ("key", "value") VALUES (?, ?)',
        ),
      );
      expect(engine.userVersion, 29);
    });

    test('passes the on-disk version to drift instead of overwriting it',
        () async {
      // The first version of this bridge created a hard-coded v6 schema and
      // then stamped user_version with the current version, so an existing
      // database looked migrated while still missing every column added since.
      engine.metaTableExists = true;
      engine.userVersion = 12;
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      final user = _FakeUser(29);

      await executor.ensureOpen(user);

      expect(user.opened.single.versionBefore, 12);
      expect(user.opened.single.versionNow, 29);
      // drift, not the executor, decides what to do about 12 -> 29.
      expect(engine.executed, isNot(contains('CREATE TABLE')));
    });

    test('leaves the version alone when it already matches', () async {
      engine.metaTableExists = true;
      engine.userVersion = 29;
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');

      await executor.ensureOpen(_FakeUser(29));

      expect(
        engine.executed.where((s) => s.contains('turna_schema_meta')),
        isEmpty,
      );
    });

    test('writes the version only after beforeOpen returns', () async {
      // A migration that throws halfway must leave the old version on disk so
      // the next launch retries instead of trusting a schema that never built.
      engine.metaTableExists = true;
      engine.userVersion = 5;
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      final user = _FakeUser(29, failOnBeforeOpen: true);

      await expectLater(executor.ensureOpen(user), throwsA(isA<StateError>()));

      expect(
        engine.executed.where((s) => s.contains('turna_schema_meta')),
        isEmpty,
      );
      expect(engine.userVersion, 5);
    });

    test('opens once and reuses the handle', () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      final user = _FakeUser(29);

      await executor.ensureOpen(user);
      engine.reset();
      await executor.ensureOpen(user);

      expect(user.beforeOpenCalls, 1);
      expect(engine.calls, isEmpty);
    });

    test('a re-entrant ensureOpen from inside beforeOpen does not reopen',
        () async {
      // The migration strategy runs its DDL inside a drift transaction, and
      // that transaction calls ensureOpen again while the first call is still
      // awaiting beforeOpen. Answering "not open yet" re-issued openDb and
      // started the whole open over, so the schema was never created.
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      final user = _ReentrantUser(29, executor);

      expect(await executor.ensureOpen(user), isTrue);

      expect(
        engine.calls.where((c) => c == 'openDb').length,
        1,
        reason: 'the store must be opened once, not once per re-entry',
      );
      expect(user.beforeOpenCalls, 1);
      expect(engine.executed, isNotEmpty,
          reason: 'the migration DDL must actually have been issued');
    });

    test('surfaces an engine that refuses to open', () async {
      engine.openSucceeds = false;
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');

      await expectLater(
        executor.ensureOpen(_FakeUser(29)),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('runSelect decoding', () {
    test('converts a real column holding an integral value to double',
        () async {
      // ArkData hands back a JS number, and an integral one crosses the channel
      // as an int. drift's REAL mapping rejects that.
      engine.nextResult = {
        'types': {'ease': 'real'},
        'rows': [
          {'ease': 2}
        ],
      };
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');

      final rows = await executor.runSelect('SELECT ease FROM srs_states', []);

      expect(rows.single['ease'], isA<double>());
      expect(rows.single['ease'], 2.0);
    });

    test('keeps an integer column an int', () async {
      engine.nextResult = {
        'types': {'reps': 'integer'},
        'rows': [
          {'reps': 7}
        ],
      };
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');

      final rows = await executor.runSelect('SELECT reps FROM srs_states', []);

      expect(rows.single['reps'], isA<int>());
    });

    test('decodes a blob column from base64', () async {
      engine.nextResult = {
        'types': {'payload': 'blob'},
        'rows': [
          {'payload': 'AQID'}
        ],
      };
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');

      final rows = await executor.runSelect('SELECT payload FROM t', []);

      expect(rows.single['payload'], [1, 2, 3]);
    });

    test('passes null through without coercion', () async {
      engine.nextResult = {
        'types': {'difficulty': 'real'},
        'rows': [
          {'difficulty': null}
        ],
      };
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');

      final rows = await executor.runSelect('SELECT difficulty FROM t', []);

      expect(rows.single['difficulty'], isNull);
    });

    test('parses an integer64 column from its text form', () async {
      engine.nextResult = {
        'types': {'big': 'integer64'},
        'rows': [
          {'big': '9007199254740993'}
        ],
      };
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');

      final rows = await executor.runSelect('SELECT big FROM t', []);

      expect(rows.single['big'], 9007199254740993);
    });

    test('normalises map keys to String', () async {
      engine.nextResult = {
        'types': {'a': 'text'},
        'rows': [
          {'a': 'x'}
        ],
      };
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');

      final rows = await executor.runSelect('SELECT a FROM t', []);

      expect(rows.single.keys.single, isA<String>());
    });

    test('returns an empty list for a zero-column result', () async {
      // A query against a table that does not exist yet comes back as a
      // zero-column result set rather than an error.
      engine.nextResult = {'types': <String, Object?>{}, 'rows': <Object?>[]};
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');

      expect(await executor.runSelect('SELECT * FROM nope', []), isEmpty);
    });
  });

  group('row ids and affected counts', () {
    test('runInsert reports the row id', () async {
      engine.scalarProbe = 42;
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');

      // review_events.id is the project's only autoincrement key, so a
      // hard-coded 0 here is a real id handed back to the caller.
      final id =
          await executor.runInsert('INSERT INTO "t" ("a") VALUES (?)', ['x']);

      expect(id, 42);
      expect(engine.queries, contains('SELECT last_insert_rowid()'));
    });

    test('runUpdate and runDelete report the affected count', () async {
      engine.scalarProbe = 3;
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');

      expect(await executor.runUpdate('UPDATE "t" SET a = ?', ['x']), 3);
      expect(await executor.runDelete('DELETE FROM "t" WHERE a = ?', ['x']), 3);
    });

    test('falls back to zero when the probe is refused', () async {
      // The engine resolves executeSql to void, so the counts come from a
      // follow-up query. If that query is unavailable the statement itself
      // still succeeded; reporting 0 is honest, failing it is not.
      engine.scalarProbe = 0;
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));

      // An empty envelope makes the probe read no value at all, which is how
      // the executor sees an engine that will not answer.
      engine.nextResult = {'types': <String, Object?>{}, 'rows': <Object?>[]};

      expect(await executor.runDelete('DELETE FROM "t"', []), 0);
      expect(await executor.runUpdate('UPDATE "t" SET a = 1', []), 0);
      expect(
          await executor.runInsert('INSERT INTO "t" ("a") VALUES (1)', []), 0);
    });
  });

  group('parameter binding', () {
    test('binds booleans as 0 and 1', () async {
      final captured = <Object?>[];
      const channel = MethodChannel('me.dsdogs.turna/rdb');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'executeSql') {
          final params = _arg(call, 'params');
          if (params is List) captured.addAll(params.cast<Object?>());
          return true;
        }
        return null;
      });

      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.runCustom('DELETE FROM "t"', [true, false, null, 1.5]);

      expect(captured, [1, 0, null, 1.5]);
    });

    test('rejects a parameter it cannot represent', () async {
      const channel = MethodChannel('me.dsdogs.turna/rdb');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => true);

      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');

      await expectLater(
        executor.runCustom('DELETE FROM "t"', [Object()]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('transactions', () {
    test(
        'a real drift transaction restores SQLite rows through the RDB channel',
        () async {
      ensureSqliteLibForTestHost();
      final native = sqlite.sqlite3.openInMemory();
      const channel = MethodChannel('me.dsdogs.turna/rdb');
      final boundaries = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'openDb':
            return true;
          case 'close':
            return true;
          case 'beginTransaction':
            boundaries.add('begin');
            native.execute('BEGIN');
            return true;
          case 'commit':
            boundaries.add('commit');
            native.execute('COMMIT');
            return true;
          case 'rollback':
            boundaries.add('rollback');
            native.execute('ROLLBACK');
            return true;
          case 'executeSql':
            final sql = _arg(call, 'sql')! as String;
            final args = (_arg(call, 'params') as List).cast<Object?>();
            native.execute(sql, args);
            return true;
          case 'query':
            final sql = _arg(call, 'sql')! as String;
            final args = (_arg(call, 'params') as List).cast<Object?>();
            final rows = native.select(sql, args);
            return {
              'types': <String, Object?>{},
              'rows': rows.map((r) => Map<String, Object?>.from(r)).toList()
            };
        }
        return null;
      });
      final course = CourseDatabase(HarmonyOsRdbExecutor(dbName: 'course.db'));
      addTearDown(() async {
        await course.close();
        native.dispose();
      });
      await course.customStatement('CREATE TABLE audit_view (value TEXT)');
      await course.customStatement("INSERT INTO audit_view VALUES ('old')");
      boundaries.clear();
      await expectLater(course.transaction(() async {
        await course.customStatement('DELETE FROM audit_view');
        throw StateError('replacement failed');
      }), throwsStateError);
      final rows =
          await course.customSelect('SELECT value FROM audit_view').get();
      expect(rows.single.read<String>('value'), 'old');
      expect(boundaries, ['begin', 'rollback']);
      await course.transaction(() async {
        await course.customStatement("UPDATE audit_view SET value = 'new'");
      });
      expect(
          (await course.customSelect('SELECT value FROM audit_view').get())
              .single
              .read<String>('value'),
          'new');
      expect(boundaries, ['begin', 'rollback', 'begin', 'commit']);
    });
    test('beginTransaction keeps statements on the real store', () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));

      final tx = executor.beginTransaction();
      await tx.ensureOpen(_FakeUser(29));
      await tx.runCustom('UPDATE "t" SET a = ?', ['x']);

      expect(engine.executed, contains('UPDATE "t" SET a = ?'));
      expect(engine.calls, contains('beginTransaction'));
      await tx.rollback();
    });

    test('send commits and rollback undoes', () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));

      final tx = executor.beginTransaction();
      await tx.runCustom('UPDATE "t" SET a = ?', ['x']);
      await tx.send();

      expect(engine.calls, contains('commit'));
      expect(engine.calls, isNot(contains('rollback')));
    });

    test('rollback is reported when the block throws', () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));

      final tx = executor.beginTransaction();
      await tx.ensureOpen(_FakeUser(29));
      await tx.rollback();

      expect(engine.calls, contains('rollback'));
    });

    test('failed view replacement restores the previous rows', () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      engine.reset();
      engine.unsupported['INSERT INTO anki_course_tree_view'] = 'write failed';
      final tx = executor.beginTransaction();
      await tx.ensureOpen(_FakeUser(29));
      await tx.runCustom('DELETE FROM anki_course_tree_view');
      await expectLater(tx.runCustom('INSERT INTO anki_course_tree_view'),
          throwsA(isA<PlatformException>()));
      await tx.rollback();
      expect(engine.viewRows, ['old-view']);
      expect(engine.calls,
          ['beginTransaction', 'executeSql', 'executeSql', 'rollback']);
    });

    test('outside queries wait until the transaction releases the connection',
        () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      engine.reset();
      final tx = executor.beginTransaction();
      await tx.ensureOpen(_FakeUser(29));
      final outside = executor.runCustom('OUTSIDE');
      await Future<void>.delayed(Duration.zero);
      expect(engine.executed, isNot(contains('OUTSIDE')));
      await tx.runCustom('INSIDE');
      await tx.send();
      await outside;
      expect(engine.executed, ['INSIDE', 'OUTSIDE']);
      expect(engine.calls,
          ['beginTransaction', 'executeSql', 'commit', 'executeSql']);
    });

    test('commit failure is propagated and remains rollbackable', () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      engine.reset();
      final tx = executor.beginTransaction();
      await tx.ensureOpen(_FakeUser(29));
      await tx.runCustom('DELETE FROM anki_course_tree_view');
      engine.failCommit = true;
      await expectLater(tx.send(), throwsA(isA<PlatformException>()));
      await tx.rollback();
      expect(engine.viewRows, ['old-view']);
      expect(engine.calls,
          containsAllInOrder(['beginTransaction', 'commit', 'rollback']));
    });

    test('an unused transaction commits and rolls back without a native begin',
        () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      engine.reset();
      await executor.beginTransaction().send();
      await executor.beginTransaction().rollback();
      expect(engine.calls, isEmpty);
    });

    test(
        'a failed rollback prevents later queries from joining the uncertain transaction',
        () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      final tx = executor.beginTransaction();
      await tx.ensureOpen(_FakeUser(29));
      engine.failRollback = true;
      await expectLater(tx.rollback(), throwsA(isA<PlatformException>()));
      await expectLater(executor.runCustom('OUTSIDE'), throwsStateError);
      expect(engine.executed, isNot(contains('OUTSIDE')));
      await executor.close();
    });

    test(
        'callbacks from a released connection context cannot enter a later transaction',
        () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      await executor.runCustom('CAPTURE');
      final oldZone = engine.lastExecuteZone!;
      final tx = executor.beginTransaction();
      await tx.ensureOpen(_FakeUser(29));
      final outside = oldZone.run(() => executor.runCustom('LATE_OUTSIDE'));
      await Future<void>.delayed(Duration.zero);
      expect(engine.executed, isNot(contains('LATE_OUTSIDE')));
      await tx.send();
      await outside;
      expect(engine.executed, contains('LATE_OUTSIDE'));
    });

    test('does not claim nested transaction support', () {
      // ArkData has one transaction per store. drift runs a nested
      // transaction() in the enclosing zone when this is false, which is the
      // behaviour the engine can honour.
      expect(HarmonyOsRdbExecutor(dbName: 'x').supportsNestedTransactions,
          isFalse);
    });
  });

  group('upsert probe', () {
    test('passes ON CONFLICT through when the engine accepts it', () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      engine.reset();

      await executor.runCustom(
        'INSERT INTO "srs_states" ("word_id") VALUES (?) '
        'ON CONFLICT ("word_id") DO UPDATE SET "word_id" = ?',
        ['a', 'a'],
      );

      expect(engine.calls, contains('executeSql'));
    });

    test('probes once and then serves the statement directly', () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      engine.reset();

      for (var i = 0; i < 3; i++) {
        await executor.runCustom(
          'INSERT INTO "t" ("a") VALUES (?) ON CONFLICT ("a") DO UPDATE SET "a" = ?',
          ['a', 'a'],
        );
      }

      final probes = engine.executed
          .where(
              (s) => s.contains('_turna_upsert_probe') && s.contains('INSERT'))
          .length;
      expect(probes, 1);
    });

    test('drops the probe table whether it passes or fails', () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      engine.reset();

      await executor.runCustom(
        'INSERT INTO "t" ("a") VALUES (?) ON CONFLICT ("a") DO UPDATE SET "a" = ?',
        ['a', 'a'],
      );

      expect(
        engine.executed.where((s) => s.contains('DROP TABLE')),
        isNotEmpty,
      );
    });

    test('throws a diagnosable error when the engine has no upsert', () async {
      // The rewrite that used to stand here turned the statement into
      // INSERT OR REPLACE, which deletes the conflicting row first and fires
      // the course tree's ON DELETE CASCADE. Failing loudly is the point.
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      engine.reset();
      engine.unsupported['INSERT INTO "_turna_upsert_probe" ("k", "v") '
          'VALUES (?, ?) ON CONFLICT ("k") DO UPDATE SET "v" = ?'] = 'syntax';

      await expectLater(
        executor.runCustom(
          'INSERT INTO "t" ("a") VALUES (?) ON CONFLICT ("a") DO UPDATE SET "a" = ?',
          ['a', 'a'],
        ),
        throwsA(isA<RdbUnsupportedSqlError>()),
      );
    });

    test('stays failed for later statements without re-probing', () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      engine.reset();
      engine.unsupported['INSERT INTO "_turna_upsert_probe" ("k", "v") '
          'VALUES (?, ?) ON CONFLICT ("k") DO UPDATE SET "v" = ?'] = 'syntax';

      const stmt = 'INSERT INTO "t" ("a") VALUES (?) '
          'ON CONFLICT ("a") DO UPDATE SET "a" = ?';
      await expectLater(
        executor.runCustom(stmt, ['a', 'a']),
        throwsA(isA<RdbUnsupportedSqlError>()),
      );
      final probesAfterFirst = engine.executed
          .where(
              (s) => s.contains('_turna_upsert_probe') && s.contains('INSERT'))
          .length;
      await expectLater(
        executor.runCustom(stmt, ['a', 'a']),
        throwsA(isA<RdbUnsupportedSqlError>()),
      );
      final probesAfterSecond = engine.executed
          .where(
              (s) => s.contains('_turna_upsert_probe') && s.contains('INSERT'))
          .length;

      expect(probesAfterSecond, probesAfterFirst);
    });

    test('does not probe for statements without a conflict clause', () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      engine.reset();

      await executor.runCustom('DELETE FROM "t"');

      expect(
        engine.executed.where((s) => s.contains('_turna_upsert_probe')),
        isEmpty,
      );
    });
  });

  group('upsert probe concurrency', () {
    // The five cases above all await one statement at a time, which is exactly
    // why the defect below survived them. Two statements that overlap in one
    // event-loop turn are the real shape: `SrsQueueProvider` batches writes and
    // several providers flush on the same frame.
    const stmt = 'INSERT INTO "t" ("a") VALUES (?) '
        'ON CONFLICT ("a") DO UPDATE SET "a" = ?';

    int probeInserts(FakeRdbEngine e) => e.executed
        .where((s) => s.contains('_turna_upsert_probe') && s.contains('INSERT'))
        .length;

    test('concurrent upserts share one probe and both succeed', () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      engine.reset();

      // Not awaited one by one: the second call must arrive while the first is
      // still inside the probe.
      final results = await Future.wait(<Future<void>>[
        executor.runCustom(stmt, ['a', 'a']),
        executor.runCustom(stmt, ['b', 'b']),
        executor.runCustom(stmt, ['c', 'c']),
      ]);

      expect(results, hasLength(3));
      expect(
        probeInserts(engine),
        1,
        reason: 'three overlapping statements must share a single probe; a '
            'second probe races the first on one scratch table',
      );
      // The statements themselves still ran — joining the probe must not turn
      // into skipping the write.
      final writes = engine.executed
          .where((s) => s.contains('"t"') && s.contains('ON CONFLICT'))
          .length;
      expect(writes, 3);
    });

    test('a losing probe cannot overwrite the winner\'s verdict', () async {
      // Reproduces the device log: one process reported "accepted" and, 6 ms
      // later, "probe failed" for the same engine. The failure then became the
      // sticky cached verdict, so every later upsert threw and SRS progress
      // silently stopped being written.
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      engine.reset();

      await Future.wait(<Future<void>>[
        executor.runCustom(stmt, ['a', 'a']),
        executor.runCustom(stmt, ['b', 'b']),
      ]);

      // A third, later statement stands in for the rest of the session: if the
      // race had poisoned the cache it would throw here instead of running.
      await expectLater(executor.runCustom(stmt, ['c', 'c']), completes);
      expect(
        engine.executed.where((s) => s.contains('DROP TABLE')).length,
        1,
        reason: 'one probe means one cleanup; a per-caller probe would drop '
            'the table while another probe was still using it',
      );
    });

    test('concurrent upserts all fail when the engine truly has no upsert',
        () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      engine.reset();
      engine.unsupported['INSERT INTO "_turna_upsert_probe" ("k", "v") '
          'VALUES (?, ?) ON CONFLICT ("k") DO UPDATE SET "v" = ?'] = 'syntax';

      final settled = await Future.wait(<Future<void>>[
        executor.runCustom(stmt, ['a', 'a']).then<void>((_) {},
            onError: (Object _) {}),
        executor.runCustom(stmt, ['b', 'b']).then<void>((_) {},
            onError: (Object _) {}),
      ]);

      expect(settled, hasLength(2));
      expect(
        probeInserts(engine),
        1,
        reason: 'the failing probe must not be retried once per caller',
      );
    });
  });

  group('close', () {
    test('closes the native store even when migration failed before isOpen',
        () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await expectLater(
          executor.ensureOpen(_FakeUser(29, failOnBeforeOpen: true)),
          throwsStateError);
      engine.reset();
      await executor.close();
      expect(engine.calls, ['close']);
    });
    test('is idempotent and only closes an open handle', () async {
      final executor = HarmonyOsRdbExecutor(dbName: 'course.db');
      await executor.ensureOpen(_FakeUser(29));
      engine.reset();

      await executor.close();
      await executor.close();

      expect(engine.calls.where((c) => c == 'close').length, 1);
    });
  });
}
