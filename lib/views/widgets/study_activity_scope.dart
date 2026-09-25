// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/service/remote_backup/remote_backup_busy_gate.dart';

/// Mixin for screens that study or practice: holds the study side of the
/// backup mutual-exclusion boundary (plan P0) for the screen's lifetime.
///
/// While the scope is held, a remote backup refuses to snapshot (and a
/// running snapshot re-checks between phases). Conversely, entering the
/// scope while a backup snapshot is running returns the blocking
/// [RemoteBackupActiveException] — the screen surfaces its message instead
/// of racing scheduler/SRS writes against the snapshot.
mixin StudyActivityScopeMixin<T extends StatefulWidget> on State<T> {
  String? _heldStudyScope;

  /// Releases any previously held scope (retry paths re-enter `_start`),
  /// then enters [scope]. Returns null on success, or the blocking
  /// exception when a backup snapshot is running.
  RemoteBackupActiveException? enterStudyScope(String scope) {
    exitStudyScope();
    final gate = tryResolveStudyActivityGate();
    if (gate == null) return null;
    try {
      gate.begin(scope);
    } on RemoteBackupActiveException catch (error) {
      return error;
    }
    _heldStudyScope = scope;
    return null;
  }

  void exitStudyScope() {
    final held = _heldStudyScope;
    if (held == null) return;
    _heldStudyScope = null;
    tryResolveStudyActivityGate()?.end(held);
  }

  @override
  void dispose() {
    exitStudyScope();
    super.dispose();
  }
}
