import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/import/official_anki_staging_manager.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/course_catalog.dart';

/// Outcome of a user-confirmed ghost purge of Official Anki leftovers.
class OfficialAnkiGhostPurgeResult {
  const OfficialAnkiGhostPurgeResult({
    required this.ok,
    this.deletedEntries = 0,
    this.errorCode,
  });

  final bool ok;
  final int deletedEntries;
  final String? errorCode;
}

/// Reclaims Official profile bytes that have no catalog source to uninstall:
/// empty `collection.anki2` / media after every deck was removed, checkpoints,
/// backups, and ledger-less staging dirs.
///
/// Fail-closed when any `anki_sources` row or unfinished import attempt
/// still exists — those must go through uninstall / the repair center.
/// Does **not** delete `official_catalog.sqlite`.
class OfficialAnkiGhostPurgeService {
  const OfficialAnkiGhostPurgeService();

  Future<OfficialAnkiGhostPurgeResult> run({
    OfficialAnkiDatabase? catalog,
    OfficialAnkiPaths? paths,
    OfficialAnkiEngine? engine,
  }) async {
    final resolvedCatalog =
        catalog ?? OfficialAnkiCompositionRoot.readOnlyCatalog;
    final resolvedPaths = paths ?? OfficialAnkiCompositionRoot.locatorPaths;
    if (resolvedPaths == null) {
      return const OfficialAnkiGhostPurgeResult(
        ok: false,
        errorCode: 'capability_missing',
      );
    }
    if (resolvedCatalog != null) {
      final sources = OfficialAnkiSourceDao(resolvedCatalog).listSources(
        resolvedPaths.profileId.isEmpty
            ? CourseCatalog.officialProfileId
            : resolvedPaths.profileId,
      );
      if (sources.isNotEmpty) {
        return const OfficialAnkiGhostPurgeResult(
          ok: false,
          errorCode: 'sources_present',
        );
      }
      if (OfficialAnkiImportAttemptDao(resolvedCatalog)
          .unfinished()
          .isNotEmpty) {
        return const OfficialAnkiGhostPurgeResult(
          ok: false,
          errorCode: 'import_in_progress',
        );
      }
    }

    final resolvedEngine = engine ?? OfficialAnkiCompositionRoot.engine;
    try {
      await resolvedEngine?.closeCollection();
    } catch (_) {}
    try {
      await OfficialAnkiCompositionRoot.stagingEngine?.closeCollection();
    } catch (_) {}
    // Worker 模式下 engine.closeCollection() 是 no-op（SessionEngine 不
    // 转发该调用），collection.anki2 等文件句柄仍被 worker isolate 持有，
    // Windows 上删除会静默失败。dispose 终止 isolate 才真正释放；随后
    // 置 null，下次使用由 requireImporter 重开全新 worker。
    final liveSession = OfficialAnkiCompositionRoot.session;
    if (liveSession is OfficialAnkiSession) {
      try {
        await liveSession.dispose();
      } catch (_) {}
    }
    try {
      await OfficialAnkiCompositionRoot.stagingSession?.dispose();
    } catch (_) {}
    OfficialAnkiCompositionRoot.session = null;
    OfficialAnkiCompositionRoot.stagingSession = null;
    OfficialAnkiCompositionRoot.stagingEngine = null;

    var deleted = 0;
    deleted += await _deleteFile(resolvedPaths.collectionFile);
    deleted += await _deleteFile(
      File('${resolvedPaths.collectionFile.path}-wal'),
    );
    deleted += await _deleteFile(
      File('${resolvedPaths.collectionFile.path}-shm'),
    );
    deleted += await _deleteFile(resolvedPaths.mediaDb);
    deleted += await _deleteDir(resolvedPaths.mediaFolder);
    deleted += await _deleteDir(resolvedPaths.backups);
    deleted += await _deleteDir(
      Directory(p.join(resolvedPaths.profileRoot.path, 'checkpoints')),
    );
    deleted += await _deleteDir(resolvedPaths.tempFolder);

    final stagingRoot = Directory(
      p.join(resolvedPaths.profileRoot.parent.path, 'staging'),
    );
    if (await stagingRoot.exists()) {
      for (final entity in stagingRoot.listSync(followLinks: false)) {
        if (entity is Directory) {
          deleted += await _deleteDir(entity);
        }
      }
    }

    await resolvedPaths.ensureLayout();
    return OfficialAnkiGhostPurgeResult(ok: true, deletedEntries: deleted);
  }

  Future<int> _deleteFile(File file) async {
    try {
      if (file.existsSync()) {
        file.deleteSync();
        return 1;
      }
    } catch (_) {}
    return 0;
  }

  Future<int> _deleteDir(Directory dir) async {
    if (!dir.existsSync()) return 0;
    try {
      await OfficialAnkiStagingManager.deleteDirectory(dir);
      return 1;
    } catch (_) {
      return 0;
    }
  }
}
