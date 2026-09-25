// Package imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/di/injection.dart';

/// A backup cannot start while a study activity (review / lesson / import)
/// is running.
class RemoteBackupBusyException implements Exception {
  @override
  String toString() => '复习或导入正在进行中，请稍后再试';
}

/// A study activity cannot start while a backup snapshot is being taken.
class RemoteBackupActiveException implements Exception {
  @override
  String toString() => '远程备份正在进行中，请稍后再试';
}

/// Cross-cutting mutual-exclusion boundary between remote backups and the
/// study/import flows that write user data.
///
/// Architecture-simplification plan P0: wiring the entry busyGuard alone
/// cannot stop writes that start mid-snapshot, so the boundary works in
/// both directions for the whole snapshot period:
///
///  * study scopes ([begin]/[end]) — named scopes entered by the import
///    wizard's parse/commit work and by the review/lesson pages. A backup
///    refuses to start while any scope is held, and re-checks between
///    snapshot phases (aborts instead of packing an inconsistent archive);
///  * the backup hold ([backupEnter]/[backupExit]) — held for the entire
///    snapshot build. New study scopes throw [RemoteBackupActiveException]
///    while it is held, so the snapshot cannot race a review or import.
///
/// Uploads read immutable staging copies and run outside the hold, so
/// studying may resume while a large archive uploads. Scope names are
/// counted by depth, so nested enters (e.g. the import wizard resuming
/// through `proceedWithPath`) never release early.
class StudyActivityGate {
  final _scopes = <String, int>{};
  var _backupHolders = 0;

  @visibleForTesting
  bool get hasScopes => _scopes.isNotEmpty;

  bool get isStudyActive => _scopes.isNotEmpty;

  bool get isBackupActive => _backupHolders > 0;

  bool get isBusy => isStudyActive || isBackupActive;

  /// Enters a named study scope. Throws [RemoteBackupActiveException] while
  /// a backup snapshot is being taken — callers surface that message.
  void begin(String scope) {
    if (isBackupActive) throw RemoteBackupActiveException();
    _scopes[scope] = (_scopes[scope] ?? 0) + 1;
  }

  /// Leaves a named study scope. Unbalanced ends are ignored so a late
  /// `end` after a failed `begin` cannot corrupt the depth of another flow.
  void end(String scope) {
    final depth = _scopes[scope];
    if (depth == null) return;
    if (depth <= 1) {
      _scopes.remove(scope);
    } else {
      _scopes[scope] = depth - 1;
    }
  }

  /// Runs [body] inside a named study scope.
  Future<T> runInScope<T>(String scope, Future<T> Function() body) async {
    begin(scope);
    try {
      return await body();
    } finally {
      end(scope);
    }
  }

  /// Acquires the backup hold for the snapshot period. Throws
  /// [RemoteBackupBusyException] when a study activity is running or
  /// another backup already holds the gate.
  void backupEnter() {
    if (isBusy) throw RemoteBackupBusyException();
    _backupHolders++;
  }

  /// Mid-snapshot re-check between phases: a study activity that started
  /// despite the hold aborts the backup instead of letting it pack an
  /// inconsistent snapshot (prefs / dbs / media captured at different
  /// moments under active writes).
  void backupCheck() {
    if (isStudyActive) throw RemoteBackupBusyException();
  }

  void backupExit() {
    if (_backupHolders > 0) _backupHolders--;
  }

  /// Resets all state (test seam).
  @visibleForTesting
  void resetForTest() {
    _scopes.clear();
    _backupHolders = 0;
  }

  /// Test seam: registers a study scope WITHOUT the mutual-exclusion
  /// check, simulating a writer that bypassed [begin] entirely — the
  /// regression shape the mid-snapshot [backupCheck] exists to catch.
  @visibleForTesting
  void debugForceScope(String scope) {
    _scopes[scope] = (_scopes[scope] ?? 0) + 1;
  }
}

/// Resolves the app-wide [StudyActivityGate], or null when it has not been
/// registered (pure unit tests that never entered a study flow). Never
/// constructs side effects, so callers may treat null as "no gating".
StudyActivityGate? tryResolveStudyActivityGate() {
  if (!getIt.isRegistered<StudyActivityGate>()) return null;
  return getIt<StudyActivityGate>();
}

/// Runs [body] inside a named study scope resolved from DI; when a backup
/// snapshot is active, [onBlocked] surfaces its message instead. Used by
/// application-layer flows (import wizard) that cannot host the
/// [StudyActivityGate] dependency directly.
Future<void> runStudyActivityScope(
  String scope,
  Future<void> Function() body, {
  required void Function(String message) onBlocked,
}) async {
  final gate = tryResolveStudyActivityGate();
  if (gate == null) {
    await body();
    return;
  }
  try {
    gate.begin(scope);
  } on RemoteBackupActiveException catch (error) {
    onBlocked(error.toString());
    return;
  }
  try {
    await body();
  } finally {
    gate.end(scope);
  }
}
