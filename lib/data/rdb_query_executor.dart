// Bridges HarmonyOS native RDB (@kit.ArkData relationalStore) to drift via a
// MethodChannel, so the course database works on OHOS where the sqlite3 FFI
// library that backs `NativeDatabase` does not exist.
//
// Assembled in `_openAndMigrateCourseDatabase` in `lib/service/locator.dart`.
// The ArkTS half of this bridge is
// `ohos/entry/src/main/ets/plugins/RdbPlugin.ets`; the two sides share the
// channel name below and the `{types, rows}` envelope `runSelect` decodes.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';

import '../core/logger.dart';
import '../core/ohos_target.dart';
import 'rdb_schema_introspection.dart';

/// Thrown when the HarmonyOS RDB engine lacks a SQL feature drift depends on.
///
/// Distinct from a failed statement: the statement is valid SQLite, so this
/// means the engine is a restricted dialect, and retrying or rewriting the call
/// site cannot help.
class RdbUnsupportedSqlError implements Exception {
  const RdbUnsupportedSqlError(this.message);

  final String message;

  @override
  String toString() => 'RdbUnsupportedSqlError: $message';
}

/// Thrown when a bridge call never comes back.
///
/// The engine has at least one statement shape that hangs rather than
/// answering, so a stall has to be distinguishable from slowness or the open
/// simply never completes.
class RdbCallTimeoutError implements Exception {
  const RdbCallTimeoutError(this.statement, this.timeout);

  final String statement;
  final Duration timeout;

  @override
  String toString() =>
      'RdbCallTimeoutError: no reply within ${timeout.inSeconds}s for `$statement`';
}

/// A drift [QueryExecutor] backed by HarmonyOS RDB.
///
/// Statements cross the channel as SQL text plus positional `?` parameters,
/// exactly as they would with `NativeDatabase`; drift stays unaware of the
/// swap.
///
/// Schema handling is delegated to drift. `ensureOpen` only reports the version
/// found on disk and lets `CourseDatabase.migration` run, so the DDL comes from
/// the drift table definitions rather than a hand-maintained copy that drifts
/// out of sync with `kSchemaVersion`.
///
/// Known differences from [NativeDatabase], all forced by the engine:
///
/// - Statements run on the platform thread. `NativeDatabase` uses a background
///   isolate, so large imports block the Dart isolate's peers rather than the
///   UI thread. Every call is still asynchronous, so the UI keeps rendering.
/// - Values arrive typed by the *declared* column type, reported alongside the
///   rows, because ArkData does not distinguish a `REAL` column holding `2.0`
///   from an `INTEGER` column holding `2` across the method channel.
/// - `runInsert` recovers the row id with `last_insert_rowid()` and
///   `runUpdate`/`runDelete` recover the affected count with `changes()`,
///   because `executeSql` resolves to `void`. If either probe fails the call
///   reports 0, matching what the engine can confirm on its own.
class HarmonyOsRdbExecutor extends QueryExecutor {
  HarmonyOsRdbExecutor({required this.dbName});

  /// The channel both halves of this bridge agree on. Also asserted by
  /// `RdbPlugin.ets`, so a rename on one side fails the build on the other.
  static const MethodChannel channel = MethodChannel('me.dsdogs.turna/rdb');

  /// Table holding the schema version, in place of `PRAGMA user_version`.
  ///
  /// Created by this executor rather than by drift, so it is not part of the
  /// drift schema and survives the migration strategy's downgrade wipe — which
  /// is right, since the wipe rebuilds at the current version anyway.
  static const String kSchemaMetaTable = 'turna_schema_meta';
  static const String kSchemaVersionKey = 'schema_version';

  /// Ceiling on a single bridge call.
  ///
  /// A hung call is otherwise indistinguishable from a slow one: the open never
  /// completes and the app shows a white screen with nothing in the log. The
  /// timeout cannot cancel the native work, but it turns the failure into
  /// something that names the statement.
  static const Duration _callTimeout = Duration(seconds: 20);

  @override
  final SqlDialect dialect = SqlDialect.sqlite;

  final String dbName;

  bool _isOpen = false;
  bool _nativeOpen = false;

  /// True between entering [ensureOpen] and `beforeOpen` returning. Guards the
  /// re-entrant call that the migration strategy's transaction makes.
  bool _isOpening = false;

  /// `null` until the first `ON CONFLICT` statement probes the engine.
  bool? _upsertSupported;

  /// The in-flight probe run, claimed before any `await` so that concurrent
  /// callers join it instead of racing a second probe against the same scratch
  /// table. See [_requireUpsertSupport].
  Future<void>? _upsertProbeInFlight;

  /// Whether this executor is the OHOS target. See [isHarmonyOsTarget] for why
  /// the platform is compared by name.
  static bool get isSupportedPlatform => isHarmonyOsTarget;

  bool get supportsNestedTransactions => false;

  final Object _connectionZone = Object();
  Future<void> _connectionTail = Future<void>.value();
  Object? _activeLease;
  QueryExecutorUser? _user;
  bool _transactionUncertain = false;

  (Future<void>, Completer<void>) _reserveConnection() {
    final previous = _connectionTail;
    final released = Completer<void>();
    _connectionTail = released.future;
    return (previous, released);
  }

  Future<T> _withConnection<T>(Future<T> Function() action,
      {bool allowUncertain = false}) async {
    if (_transactionUncertain && !allowUncertain) {
      throw StateError(
          'RDB transaction outcome is unknown; close the connection before reopening');
    }
    final inherited = Zone.current[_connectionZone];
    if (inherited != null && identical(inherited, _activeLease)) {
      return action();
    }
    final (previous, released) = _reserveConnection();
    await previous;
    try {
      if (_transactionUncertain && !allowUncertain) {
        throw StateError(
            'RDB transaction outcome is unknown; close the connection before reopening');
      }
      final lease = Object();
      _activeLease = lease;
      return await runZoned(action, zoneValues: {_connectionZone: lease});
    } finally {
      _activeLease = null;
      released.complete();
    }
  }

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) =>
      _withConnection(() => _ensureOpen(user));

  Future<bool> _ensureOpen(QueryExecutorUser user) async {
    _user = user;
    if (_isOpen) return true;
    // Re-entrant calls happen inside `beforeOpen` itself: the migration
    // strategy opens a drift transaction to run its DDL, and that transaction
    // calls `ensureOpen` again while this call is still awaiting `beforeOpen`.
    // Treating that as "not open yet" re-issued `openDb` and started over, so
    // the schema was never created and the app sat on a white screen. drift
    // guards the same way: its own opening executor answers true immediately.
    if (_isOpening) return true;
    _isOpening = true;
    try {
      return await _openOnce(user);
    } finally {
      _isOpening = false;
    }
  }

  Future<bool> _openOnce(QueryExecutorUser user) async {
    final opened = await _call(
      () => channel.invokeMethod<bool>('openDb', {'name': dbName}),
      'openDb $dbName',
    );
    if (opened != true) {
      throw StateError('HarmonyOS RDB failed to open: $dbName');
    }
    _nativeOpen = true;

    final oldVersion = await _readUserVersion();
    // A freshly created SQLite file reports `user_version` 0, but drift
    // asserts `versionBefore != 0` and treats null as "no schema yet". The
    // normalization has to happen here, the same way drift's own executors do
    // it, or every new database fails the assertion instead of running
    // `onCreate`.
    final previousVersion = oldVersion == 0 ? null : oldVersion;

    await user.beforeOpen(
      this,
      OpeningDetails(previousVersion, user.schemaVersion),
    );
    // Written after `beforeOpen` so a migration that throws halfway leaves the
    // on-disk version behind, and the next launch retries instead of reporting
    // a schema that was never built.
    if (oldVersion != user.schemaVersion) {
      await _writeUserVersion(user.schemaVersion);
    }

    _isOpen = true;
    logger.d(
      'RDB open $dbName: version '
      '${previousVersion ?? 'new'} -> ${user.schemaVersion}',
    );
    return true;
  }

  @override
  Future<int> runInsert(String sql, List<Object?> args) =>
      _withConnection(() async {
        await _execute(sql, args);
        return await _probeInt('SELECT last_insert_rowid()') ?? 0;
      });

  @override
  Future<int> runUpdate(String sql, List<Object?> args) =>
      _withConnection(() async {
        await _execute(sql, args);
        return await _probeInt('SELECT changes()') ?? 0;
      });

  @override
  Future<int> runDelete(String sql, List<Object?> args) =>
      _withConnection(() async {
        await _execute(sql, args);
        return await _probeInt('SELECT changes()') ?? 0;
      });

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String sql,
    List<Object?> args,
  ) =>
      _withConnection(() => _runSelect(sql, args));

  Future<List<Map<String, Object?>>> _runSelect(
    String sql,
    List<Object?> args,
  ) async {
    final shimmed = await _answerPragma(sql);
    if (shimmed != null) return shimmed;

    final payload = await _call(
      () => channel.invokeMapMethod<String, dynamic>(
        'query',
        _toArgsMap(sql, args),
      ),
      sql,
    );
    if (payload == null) return const [];

    final types = _stringKeyedMap(payload['types']);
    final rawRows = payload['rows'];
    if (rawRows is! List) return const [];

    final rows = <Map<String, Object?>>[];
    for (final rawRow in rawRows) {
      final row = _stringKeyedMap(rawRow);
      rows.add(_coerceRow(row, types));
    }
    return rows;
  }

  @override
  Future<void> runCustom(String sql, [List<Object?>? args]) =>
      _withConnection(() => _execute(sql, args));

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _withConnection(() async {
        for (final argSet in statements.arguments) {
          await _execute(
              statements.statements[argSet.statementIndex], argSet.arguments);
        }
      });

  @override
  TransactionExecutor beginTransaction() => _HarmonyOsRdbTransaction(this);

  @override
  QueryExecutor beginExclusive() => this;

  @override
  Future<void> close() => _withConnection(() async {
        if (!_nativeOpen) return;
        await _invokeVoid('close');
        _isOpen = false;
        _nativeOpen = false;
        _transactionUncertain = false;
      }, allowUncertain: true);

  Future<void> _transactionBoundary(String method) async {
    final ok = await _call(
      () => channel.invokeMethod<bool>(method),
      method,
    );
    if (ok != true) throw StateError('RDB $method reported failure');
  }

  // --- internals ---

  Future<int?> _readUserVersion() async {
    // Not `PRAGMA user_version`. On this engine a `querySql` for a PRAGMA hands
    // back a ResultSet whose `getColumnNames()` never returns, so the promise
    // never settles and the open hangs — observed on device, not guessed: the
    // first launch after wiring this up sat on a white screen with the last log
    // line being the PRAGMA query. A table of our own is an ordinary SELECT.
    //
    // No table means no database yet, which is version 0.
    try {
      final rows = await runSelect(
        'SELECT "value" FROM $kSchemaMetaTable WHERE "key" = ?',
        [kSchemaVersionKey],
      );
      if (rows.isEmpty) return 0;
      final value = rows.first['value'];
      if (value is int) return value;
      if (value is double) return value.toInt();
      return int.tryParse('$value') ?? 0;
    } on RdbUnsupportedSqlError {
      rethrow;
    } catch (e) {
      // A missing table arrives as an error rather than an empty result on some
      // engines. Either way this is a database that has never been migrated.
      logger.d('RDB schema meta absent; treating as a new database', error: e);
      return 0;
    }
  }

  Future<void> _writeUserVersion(int version) async {
    // Plain DELETE + INSERT rather than an upsert: this runs once per launch,
    // and `ON CONFLICT ... DO UPDATE` is the very construct whose availability
    // is probed separately, so depending on it here would turn an unsupported
    // upsert into an unexplained failure during the open itself.
    await _execute(
      'CREATE TABLE IF NOT EXISTS $kSchemaMetaTable ('
      '"key" TEXT NOT NULL PRIMARY KEY, '
      '"value" INTEGER NOT NULL)',
      null,
    );
    await _execute(
      'DELETE FROM $kSchemaMetaTable WHERE "key" = ?',
      [kSchemaVersionKey],
    );
    await _execute(
      'INSERT INTO $kSchemaMetaTable ("key", "value") VALUES (?, ?)',
      [kSchemaVersionKey, version],
    );
  }

  /// Reads a single-cell integer probe, reporting `null` when the engine refuses
  /// it. Callers turn that into 0 rather than failing the statement they were
  /// trying to get a result for.
  Future<int?> _probeInt(String sql) async {
    try {
      final rows = await runSelect(sql, const []);
      if (rows.isEmpty) return null;
      final value = rows.first.values.first;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    } catch (e) {
      logger.w('RDB probe failed: $sql', error: e);
      return null;
    }
  }

  /// Answers `PRAGMA table_info` from the stored CREATE statement.
  ///
  /// Returns null when [sql] is not that pragma, so the caller sends it to the
  /// engine as usual. Every other pragma is deliberately not special-cased:
  /// they hang, and a hang that is turned into a loud error beats one that is
  /// papered over.
  Future<List<Map<String, Object?>>?> _answerPragma(String sql) async {
    final match = RegExp(
            r'^\s*pragma\s+table_info\(\s*"?([A-Za-z0-9_]+)"?\s*\)\s*;?\s*$',
            caseSensitive: false)
        .firstMatch(sql);
    if (match == null) return null;

    final table = match.group(1)!;
    logger.d('RDB: answering PRAGMA table_info($table) from sqlite_master');
    final rows = await runSelect(
      'SELECT "sql" AS "ddl" FROM sqlite_master '
      'WHERE "type" = ? AND "name" = ?',
      ['table', table],
    );
    if (rows.isEmpty) return const [];

    final ddl = rows.first['ddl'];
    if (ddl is! String) return const [];
    final columns = parseCreateTableColumns(ddl);
    return [
      for (var i = 0; i < columns.length; i++)
        {
          'cid': i,
          'name': columns[i].name,
          'type': columns[i].type,
          'notnull': 0,
          'dflt_value': null,
          'pk': 0,
        }
    ];
  }

  Future<void> _execute(String sql, List<Object?>? args) async {
    logger.d('RDB sql: $sql');
    if (sql.toUpperCase().contains('ON CONFLICT')) {
      await _requireUpsertSupport();
    }
    final ok = await _call(
      () => channel.invokeMethod<bool>(
        'executeSql',
        _toArgsMap(sql, args ?? const []),
      ),
      sql,
    );
    if (ok != true) {
      throw StateError('RDB execute reported failure: $sql');
    }
  }

  /// Runs one bridge call under [_callTimeout], naming the statement in the
  /// failure so a stall points at the query that stalled.
  Future<T?> _call<T>(Future<T?> Function() invoke, String sql) async {
    try {
      return await invoke().timeout(_callTimeout);
    } on TimeoutException {
      throw RdbCallTimeoutError(sql, _callTimeout);
    }
  }

  /// Verifies once that the engine accepts `ON CONFLICT ... DO UPDATE`, which
  /// drift emits for every `insertOnConflictUpdate`.
  ///
  /// The alternative is to rewrite the statement, and the obvious rewrite is
  /// wrong: `INSERT OR REPLACE` deletes the conflicting row before inserting,
  /// which fires the `ON DELETE CASCADE` on the course tree and destroys the
  /// child rows of whatever it upserts. A correct rewrite has to reproduce
  /// per-column updates, so it is not something to guess at on a platform that
  /// cannot be exercised from CI. Probing turns an ambiguous per-statement
  /// failure into one recorded diagnosis plus an error that names the cause.
  Future<void> _requireUpsertSupport() async {
    final verdict = _upsertSupported;
    if (verdict != null) {
      if (!verdict) {
        throw const RdbUnsupportedSqlError(
          'HarmonyOS RDB rejected `ON CONFLICT ... DO UPDATE`',
        );
      }
      return;
    }

    // Claim the probe synchronously, before the first `await` in
    // [_runUpsertProbe], and let every later caller join that one run.
    //
    // This is the same defect class as the re-entrant `ensureOpen` guarded
    // above and the re-entrant `setEngine` in `TtsAvailabilityChecker`: two
    // callers both read "not probed yet", both run the probe, and the loser
    // fails — because the probe creates and drops one scratch table and both
    // runs race on it. The device log caught exactly that, 6 ms apart inside a
    // single process:
    //
    //   RDB upsert probe: ON CONFLICT DO UPDATE accepted
    //   RDB upsert probe failed; ON CONFLICT ... DO UPDATE is unavailable
    //
    // and the loser then wrote `false` over the winner's `true`. That verdict
    // is sticky, so for the rest of the session every upsert threw, and
    // `SrsQueueProvider` only logs that — SRS progress stopped persisting with
    // nothing but a warning to show for it. A capability that is sometimes
    // reported wrong is worse than one reported missing, because the
    // diagnosis then points at the platform instead of at this file.
    final inFlight = _upsertProbeInFlight;
    if (inFlight != null) {
      await inFlight;
      // Re-read rather than assume the winner succeeded: a joiner must fail
      // identically instead of going on to run a statement the engine has just
      // been shown to reject.
      if (_upsertSupported != true) {
        throw const RdbUnsupportedSqlError(
          'HarmonyOS RDB rejected `ON CONFLICT ... DO UPDATE`',
        );
      }
      return;
    }

    final done = Completer<void>();
    _upsertProbeInFlight = done.future;
    try {
      await _runUpsertProbe();
    } finally {
      // Completed without an error on purpose. Joiners re-read the cached
      // verdict and raise their own diagnosable error, so one failing probe
      // does not fan out into N copies of the raw platform exception.
      if (!done.isCompleted) done.complete();
      if (identical(_upsertProbeInFlight, done.future)) {
        _upsertProbeInFlight = null;
      }
    }
  }

  /// Runs the probe once and records the verdict. Only [_requireUpsertSupport]
  /// calls this, and only after claiming [_upsertProbeInFlight].
  Future<void> _runUpsertProbe() async {
    const probeTable = '_turna_upsert_probe';
    try {
      await channel.invokeMethod<bool>('executeSql', {
        'sql': 'CREATE TABLE IF NOT EXISTS $probeTable '
            '("k" TEXT PRIMARY KEY, "v" INTEGER NOT NULL)',
        'params': <Object?>[],
      });
      // The shape drift emits: values first, then one placeholder per SET
      // column. If the engine parses this it can run the project's upserts.
      await channel.invokeMethod<bool>('executeSql', {
        'sql': 'INSERT INTO "$probeTable" ("k", "v") VALUES (?, ?) '
            'ON CONFLICT ("k") DO UPDATE SET "v" = ?',
        'params': <Object?>['probe', 1, 2],
      });
      _upsertSupported = true;
      logger.d('RDB upsert probe: ON CONFLICT DO UPDATE accepted');
    } catch (e) {
      _upsertSupported = false;
      logger.w(
        'RDB upsert probe failed; ON CONFLICT ... DO UPDATE is unavailable on '
        'this device, so course seeding will fail. See ADR 0047.',
        error: e,
      );
      throw const RdbUnsupportedSqlError(
        'HarmonyOS RDB rejected `ON CONFLICT ... DO UPDATE`',
      );
    } finally {
      // Best effort: a leftover probe table is inert, and failing the open
      // because the cleanup failed would be worse than the table.
      try {
        await channel.invokeMethod<bool>('executeSql', {
          'sql': 'DROP TABLE IF EXISTS $probeTable',
          'params': <Object?>[],
        });
      } catch (e) {
        // Dropping a scratch table is safe to skip.
      }
    }
  }

  Future<void> _invokeVoid(String method) async {
    try {
      await _call(() => channel.invokeMethod<void>(method), method);
    } catch (e, st) {
      // A store that is already gone makes these meaningless, and the caller
      // is tearing the database down anyway.
      logger.w('RDB $method failed', error: e, stackTrace: st);
    }
  }

  Map<String, dynamic> _toArgsMap(String sql, List<Object?> args) => {
        'sql': sql,
        'params': args.map(_serializeParam).toList(),
      };

  /// Encodes one bound parameter for the method channel.
  ///
  /// ArkData binds `int`, `double`, `string` and `null`; `bool` is written as
  /// 0/1 because drift's sqlite dialect stores booleans that way. `Uint8List`
  /// is base64 because the standard codec has no byte-array mapping, matching
  /// how `RdbPlugin.ets` encodes a BLOB cell.
  Object? _serializeParam(Object? value) {
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;
    if (value is int || value is double || value is String) return value;
    if (value is Uint8List) return base64Encode(value);
    if (value is List<int>) return base64Encode(Uint8List.fromList(value));
    throw ArgumentError('RDB cannot bind a ${value.runtimeType} parameter');
  }

  static Map<String, dynamic> _stringKeyedMap(Object? value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry('$k', v));
    }
    return const <String, dynamic>{};
  }

  /// Converts one raw row into the Dart types drift expects, following the
  /// declared column types the plugin reported.
  ///
  /// The two conversions that matter: a `real` column holding an integral value
  /// arrives as a Dart `int` and has to become a `double`, or drift rejects the
  /// row against its `REAL` mapping; and a `blob` arrives base64-encoded.
  static Map<String, Object?> _coerceRow(
    Map<String, dynamic> row,
    Map<String, dynamic> types,
  ) {
    return row.map((column, value) {
      if (value == null) return MapEntry(column, null);
      return MapEntry(column, _coerceValue(value, types[column]));
    });
  }

  static Object? _coerceValue(Object? value, Object? type) {
    switch (type) {
      case 'real':
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value);
        return value;
      case 'integer':
        if (value is double) return value.toInt();
        if (value is String) return int.tryParse(value);
        return value;
      case 'integer64':
        // Beyond 2^53 the engine reads it as text to keep precision.
        if (value is String) return int.tryParse(value) ?? value;
        return value;
      case 'blob':
        if (value is String) {
          try {
            return base64Decode(value);
          } on FormatException {
            return value;
          }
        }
        return value;
      default:
        return value;
    }
  }
}

/// A transaction holds the shared RDB connection until commit or rollback.
/// Other requests cannot accidentally become part of its native transaction.
class _HarmonyOsRdbTransaction extends QueryExecutor
    implements TransactionExecutor {
  _HarmonyOsRdbTransaction(this.owner);

  final HarmonyOsRdbExecutor owner;
  Future<void>? _opening;
  Completer<void>? _released;
  Object? _lease;
  bool _started = false;
  bool _finished = false;

  @override
  SqlDialect get dialect => owner.dialect;
  @override
  bool get supportsNestedTransactions => false;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async {
    if (_finished) throw StateError('RDB transaction is already finished');
    await (_opening ??= _begin(user));
    return true;
  }

  Future<void> _begin(QueryExecutorUser user) async {
    await owner.ensureOpen(user);
    // A migration already holds the connection inside beforeOpen. Reserving
    // it again there would deadlock that outer open.
    final inherited = Zone.current[owner._connectionZone];
    if (inherited == null || !identical(inherited, owner._activeLease)) {
      final (previous, released) = owner._reserveConnection();
      _released = released;
      await previous;
      _lease = Object();
      owner._activeLease = _lease;
    } else {
      _lease = inherited;
    }
    try {
      await _onConnection(() => owner._transactionBoundary('beginTransaction'));
      _started = true;
    } catch (_) {
      owner._transactionUncertain = true;
      _release();
      rethrow;
    }
  }

  Future<T> _onConnection<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {owner._connectionZone: _lease});

  Future<T> _run<T>(Future<T> Function() action) async {
    final user = owner._user;
    if (user == null) throw StateError('RDB database has not been opened');
    await ensureOpen(user);
    return _onConnection(action);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
          String sql, List<Object?> args) =>
      _run(() => owner.runSelect(sql, args));
  @override
  Future<int> runInsert(String sql, List<Object?> args) =>
      _run(() => owner.runInsert(sql, args));
  @override
  Future<int> runUpdate(String sql, List<Object?> args) =>
      _run(() => owner.runUpdate(sql, args));
  @override
  Future<int> runDelete(String sql, List<Object?> args) =>
      _run(() => owner.runDelete(sql, args));
  @override
  Future<void> runCustom(String sql, [List<Object?>? args]) =>
      _run(() => owner.runCustom(sql, args));
  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _run(() => owner.runBatched(statements));
  @override
  TransactionExecutor beginTransaction() => throw UnsupportedError(
      'HarmonyOS RDB does not support nested transactions');
  @override
  QueryExecutor beginExclusive() => this;
  @override
  Future<void> send() => _finish(rollback: false);
  @override
  Future<void> rollback() => _finish(rollback: true);
  @override
  Future<void> close() => rollback();

  Future<void> _finish({required bool rollback}) async {
    if (_finished) return;
    final opening = _opening;
    if (opening == null) {
      _finished = true;
      return;
    }
    await opening;
    if (!_started) return;
    var succeeded = false;
    try {
      await _onConnection(() => owner._transactionBoundary(
            rollback ? 'rollback' : 'commit',
          ));
      succeeded = true;
    } catch (_) {
      if (rollback) owner._transactionUncertain = true;
      rethrow;
    } finally {
      // A failed commit leaves the transaction alive for drift's rollback.
      if (succeeded || rollback) {
        _finished = true;
        _release();
      }
    }
  }

  void _release() {
    final released = _released;
    if (released != null && !released.isCompleted) {
      if (identical(owner._activeLease, _lease)) owner._activeLease = null;
      released.complete();
    }
  }
}
