import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

class OfficialAnkiCheckpointRow {
  const OfficialAnkiCheckpointRow({
    required this.checkpointId,
    required this.attemptId,
    required this.sourceId,
    required this.relativePath,
    required this.state,
    required this.bytes,
  });

  final String checkpointId;
  final String attemptId;
  final String sourceId;
  final String relativePath;
  final String state;
  final int bytes;
}

class OfficialAnkiCheckpointDao {
  OfficialAnkiCheckpointDao(this._database);

  final OfficialAnkiDatabase _database;
  Database get _db => _database.handle;

  OfficialAnkiCheckpointRow? findByAttempt(String attemptId) {
    final rows = _db.select(
      'SELECT * FROM anki_checkpoint_files WHERE attempt_id = ?',
      [attemptId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return OfficialAnkiCheckpointRow(
      checkpointId: row['checkpoint_id'] as String,
      attemptId: row['attempt_id'] as String,
      sourceId: row['source_id'] as String,
      relativePath: row['relative_path'] as String,
      state: row['state'] as String,
      bytes: (row['bytes'] as num?)?.toInt() ?? 0,
    );
  }

  List<OfficialAnkiCheckpointRow> listReady(String sourceId) {
    return _db
        .select(
          "SELECT * FROM anki_checkpoint_files WHERE source_id = ? "
          "AND state = 'ready'",
          [sourceId],
        )
        .map(
          (row) => OfficialAnkiCheckpointRow(
            checkpointId: row['checkpoint_id'] as String,
            attemptId: row['attempt_id'] as String,
            sourceId: row['source_id'] as String,
            relativePath: row['relative_path'] as String,
            state: row['state'] as String,
            bytes: (row['bytes'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  int resolvedReadyCount() {
    final row = _db.select(
      "SELECT COUNT(*) AS n FROM anki_checkpoint_files WHERE state = 'ready'",
    ).first;
    return row['n'] as int;
  }

  void upsertCreating({
    required String checkpointId,
    required String attemptId,
    required String sourceId,
    required String relativePath,
    required int nowMillis,
  }) {
    _db.execute(
      '''
INSERT INTO anki_checkpoint_files (
  checkpoint_id, attempt_id, source_id, relative_path, state, bytes,
  created_at_millis, updated_at_millis
) VALUES (?, ?, ?, ?, ?, 0, ?, ?)
ON CONFLICT(checkpoint_id) DO UPDATE SET
  state = excluded.state,
  updated_at_millis = excluded.updated_at_millis
''',
      [
        checkpointId,
        attemptId,
        sourceId,
        relativePath,
        OfficialAnkiCheckpointFileState.creating.wire,
        nowMillis,
        nowMillis,
      ],
    );
  }

  void markReady({
    required String checkpointId,
    required int bytes,
    required int nowMillis,
    String? sha256,
    int? preImportGeneration,
  }) {
    _db.execute(
      '''
UPDATE anki_checkpoint_files SET
  state = ?, bytes = ?, sha256 = COALESCE(?, sha256),
  pre_import_generation = COALESCE(?, pre_import_generation),
  updated_at_millis = ?
WHERE checkpoint_id = ?
''',
      [
        OfficialAnkiCheckpointFileState.ready.wire,
        bytes,
        sha256,
        preImportGeneration,
        nowMillis,
        checkpointId,
      ],
    );
  }

  void markReleased({
    required String checkpointId,
    required int nowMillis,
  }) {
    _db.execute(
      '''
UPDATE anki_checkpoint_files SET
  state = ?, released_at_millis = ?, updated_at_millis = ?
WHERE checkpoint_id = ?
''',
      [
        OfficialAnkiCheckpointFileState.released.wire,
        nowMillis,
        nowMillis,
        checkpointId,
      ],
    );
  }

  /// Copy the live collection into `checkpoints/<attemptId>.anki2` when the
  /// file exists. Import-saga checkpoints are internal rollback assets.
  Future<String> materializeFromCollection({
    required OfficialAnkiPaths paths,
    required String attemptId,
    required String sourceId,
    required int nowMillis,
  }) async {
    final dir = Directory('${paths.profileRoot.path}/checkpoints');
    await dir.create(recursive: true);
    final checkpointId = 'ckpt-$attemptId';
    final relative = 'checkpoints/$checkpointId.anki2';
    upsertCreating(
      checkpointId: checkpointId,
      attemptId: attemptId,
      sourceId: sourceId,
      relativePath: relative,
      nowMillis: nowMillis,
    );
    final dest = File('${paths.profileRoot.path}/$relative');
    if (paths.collectionFile.existsSync()) {
      await paths.collectionFile.copy(dest.path);
    } else {
      await dest.writeAsBytes(const <int>[], flush: true);
    }
    final bytes = dest.existsSync() ? dest.lengthSync() : 0;
    String? digest;
    if (dest.existsSync() && dest.lengthSync() > 0) {
      digest = sha256.convert(dest.readAsBytesSync()).toString();
    }
    markReady(
      checkpointId: checkpointId,
      bytes: bytes,
      nowMillis: nowMillis,
      sha256: digest,
    );
    return checkpointId;
  }

  Future<int> releaseFile({
    required OfficialAnkiPaths paths,
    required String checkpointId,
    required int nowMillis,
  }) async {
    final rows = _db.select(
      'SELECT relative_path FROM anki_checkpoint_files WHERE checkpoint_id = ?',
      [checkpointId],
    );
    if (rows.isEmpty) return 0;
    final relative = rows.first['relative_path'] as String;
    final file = File('${paths.profileRoot.path}/$relative');
    var bytes = 0;
    if (file.existsSync()) {
      bytes = file.lengthSync();
      file.deleteSync();
    }
    markReleased(checkpointId: checkpointId, nowMillis: nowMillis);
    return bytes;
  }

  int sweepReleasedOrphans(OfficialAnkiPaths paths) {
    final rows = _db.select(
      "SELECT checkpoint_id, relative_path FROM anki_checkpoint_files "
      "WHERE state = 'released'",
    );
    var removed = 0;
    for (final row in rows) {
      final file = File(
        '${paths.profileRoot.path}/${row['relative_path'] as String}',
      );
      if (file.existsSync()) {
        file.deleteSync();
        removed++;
      }
    }
    return removed;
  }
}
