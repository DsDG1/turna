import 'dart:convert';
import 'dart:io';

import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_sqlite.dart';
import 'package:sqlite3/sqlite3.dart';

/// Read-only storage census (doc 41 S0). Receipts contain only ids, hashes,
/// counts, bytes, phases and error codes.
class OfficialAnkiStorageAudit {
  const OfficialAnkiStorageAudit();

  Map<String, Object?> snapshot({
    required OfficialAnkiDatabase catalog,
    OfficialAnkiPaths? paths,
    String? profileId,
  }) {
    final db = catalog.handle;
    int count(String sql, [List<Object?> args = const []]) {
      final row = db.select(sql, args).first;
      return (row.values.first as num?)?.toInt() ?? 0;
    }

    final sourcesByState = <String, int>{};
    for (final row in db.select(
      'SELECT state, COUNT(*) AS n FROM anki_sources '
      'GROUP BY state',
    )) {
      sourcesByState[row['state'] as String] = row['n'] as int;
    }
    final attemptsByState = <String, int>{};
    for (final row in db.select(
      'SELECT state, COUNT(*) AS n FROM anki_import_attempts '
      'GROUP BY state',
    )) {
      attemptsByState[row['state'] as String] = row['n'] as int;
    }

    final files = <String, int>{};
    if (paths != null) {
      files['collection.anki2'] = _size(paths.collectionFile);
      files['collection.media.db2'] = _size(paths.mediaDb);
      files['official_catalog.sqlite'] = _size(paths.catalogFile);
      files['media_dir'] = _dirSize(paths.mediaFolder);
      files['backups'] = _dirSize(paths.backups);
      files['checkpoints'] =
          _dirSize(Directory('${paths.profileRoot.path}/checkpoints'));
    }

    Map<String, int> sqlitePages(File file) {
      if (!file.existsSync()) {
        return const {'page_count': 0, 'freelist_count': 0, 'page_size': 0};
      }
      ensureOfficialAnkiSqlite();
      Database? handle;
      try {
        handle = sqlite3.open(file.path, mode: OpenMode.readOnly);
        int pragma(String name) =>
            (handle!.select('PRAGMA $name').first.values.first as num?)
                ?.toInt() ??
            0;
        return {
          'page_count': pragma('page_count'),
          'freelist_count': pragma('freelist_count'),
          'page_size': pragma('page_size'),
        };
      } catch (_) {
        return const {'page_count': 0, 'freelist_count': 0, 'page_size': 0};
      } finally {
        handle?.dispose();
      }
    }

    return <String, Object?>{
      'profileId': profileId ?? paths?.profileId,
      'sourcesByState': sourcesByState,
      'attemptsByState': attemptsByState,
      'sourceCardAssociations': count('SELECT COUNT(*) FROM anki_source_cards'),
      'projectionMappings':
          count('SELECT COUNT(*) FROM anki_projection_mappings'),
      'checkpointReady': count(
        "SELECT COUNT(*) FROM anki_checkpoint_files WHERE state = 'ready'",
      ),
      'maintenancePending': count(
        "SELECT COUNT(*) FROM anki_maintenance_jobs "
        "WHERE state IN ('pending','retry_wait','running')",
      ),
      'files': files,
      if (paths != null) 'collectionPages': sqlitePages(paths.collectionFile),
      if (paths != null) 'catalogPages': sqlitePages(paths.catalogFile),
    };
  }

  String encode(Map<String, Object?> snapshot) => jsonEncode(snapshot);

  static int _size(File file) => file.existsSync() ? file.lengthSync() : 0;

  static int _dirSize(Directory dir) {
    if (!dir.existsSync()) return 0;
    var total = 0;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += entity.lengthSync();
        } catch (_) {}
      }
    }
    return total;
  }
}
