import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/diagnostics/performance_trace.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/core/log_capture.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/audio/anki_audio_resolver.dart';
import 'storage_maintenance_platform_stub.dart'
    if (dart.library.io) 'storage_maintenance_platform_io.dart' as platform;

/// How a scanned artifact may be reclaimed. The scanner never deletes
/// anything; these policies tell the diagnostics UI which actions exist.
enum StorageCleanupPolicy {
  /// User data (imports, collections, projections, SRS) — removed only
  /// through the unified uninstall saga, never by a cache sweep.
  deleteSaga,

  /// Database pages that a user-confirmed compact (VACUUM) could return.
  optimize,

  /// Regenerable cache — safe to clear in one tap.
  safeClear,

  /// Suspicious ownership (orphan media dirs) — dry-run report first, then
  /// per-item confirmation.
  confirmOnly,
}

/// One billed disk surface: a category, an owning id, its physical size,
/// and the policy that governs reclaiming it.
class StorageArtifactReport {
  const StorageArtifactReport({
    required this.category,
    required this.ownerId,
    required this.label,
    required this.physicalBytes,
    required this.fileCount,
    required this.cleanupPolicy,
    this.orphaned = false,
  });

  final StorageArtifactCategory category;
  final String ownerId;
  final String label;
  final int physicalBytes;
  final int fileCount;
  final StorageCleanupPolicy cleanupPolicy;
  final bool orphaned;
}

enum StorageArtifactCategory {
  mainDatabase,
  legacyAnki,
  legacyAnkiMedia,
  officialAnki,
  regenerableCache,
  logs,
}

/// Read-only storage inventory across every Anki-related surface (Plan 1
/// Phase 3). Aggregates the main database, legacy imports/media, the
/// official collection directory, regenerable caches, and logs — each byte
/// attributed to a category, owner, and cleanup policy. Orphan detection
/// cross-checks media directories against `anki_imports` rows; nothing is
/// ever deleted by this service.
class StorageInventoryReport {
  const StorageInventoryReport({
    required this.artifacts,
    required this.databaseWalBytes,
    required this.databaseShmBytes,
    required this.freelistBytes,
    required this.aiCacheEntries,
    required this.scannedAt,
  });

  final List<StorageArtifactReport> artifacts;
  final int databaseWalBytes;
  final int databaseShmBytes;
  final int freelistBytes;

  /// Entry count is reported separately because the AI cache is keyed in
  /// memory; a byte figure would be fabricated.
  final int aiCacheEntries;
  final DateTime scannedAt;

  StorageArtifactReport? artifact(StorageArtifactCategory category) {
    for (final a in artifacts) {
      if (a.category == category) return a;
    }
    return null;
  }

  int get totalPhysicalBytes =>
      artifacts.fold(0, (sum, a) => sum + a.physicalBytes);

  int get safelyReclaimableBytes => artifacts
      .where((a) => a.cleanupPolicy == StorageCleanupPolicy.safeClear)
      .fold(0, (sum, a) => sum + a.physicalBytes);

  List<StorageArtifactReport> get orphans =>
      artifacts.where((a) => a.orphaned).toList();

  List<StorageArtifactReport> get mediaDirsByOwner => artifacts
      .where((a) => a.category == StorageArtifactCategory.legacyAnkiMedia)
      .toList();
}

class StorageInventoryService {
  const StorageInventoryService();

  Future<StorageInventoryReport> scan() async {
    final trace = Stopwatch()..start();
    final artifacts = <StorageArtifactReport>[];
    final db = getIt<CourseDatabase>();

    // ── Main database: file, WAL, SHM, and freelist ────────────────────
    var walBytes = 0;
    var shmBytes = 0;
    var freelistBytes = 0;
    var dbBytes = 0;
    final mainFile = await _mainDatabasePath(db);
    if (mainFile != null) {
      dbBytes = await platform.fileSizeBytes(mainFile);
      walBytes = await platform.fileSizeBytes('$mainFile-wal');
      shmBytes = await platform.fileSizeBytes('$mainFile-shm');
      freelistBytes = await _freelistBytes(db);
    } else {
      // In-memory database (tests): page stats still answer.
      freelistBytes = await _freelistBytes(db);
    }
    artifacts.add(StorageArtifactReport(
      category: StorageArtifactCategory.mainDatabase,
      ownerId: '',
      label: 'course.db',
      physicalBytes: dbBytes,
      fileCount: dbBytes > 0 ? 1 : 0,
      cleanupPolicy: StorageCleanupPolicy.optimize,
    ));

    // ── Legacy Anki: import rows + per-import media directories ────────
    final imports = await AnkiImportDao(db).getAll();
    artifacts.add(StorageArtifactReport(
      category: StorageArtifactCategory.legacyAnki,
      ownerId: '',
      label: '${imports.length} imports '
          '(${imports.where((i) => i.status == 'failed').length} failed)',
      physicalBytes: 0,
      fileCount: imports.length,
      cleanupPolicy: StorageCleanupPolicy.deleteSaga,
    ));

    final mediaBase =
        p.join(await AnkiAudioResolver().getMediaBasePath(), 'anki_media');
    final ownedIds = imports.map((i) => i.importId).toSet();
    // Exact import rows own media even while a course is staging/hidden.
    // Course visibility is not an ownership fact, and prefix comparisons can
    // confuse sibling ids such as `abc` and `abc-extra`.
    final mediaDirs = await _listSubdirectories(mediaBase);
    for (final dir in mediaDirs) {
      final size = await platform.directorySizeBytes(dir.path);
      final name = p.basename(dir.path);
      final hasOwner = ownedIds.contains(name);
      artifacts.add(StorageArtifactReport(
        category: StorageArtifactCategory.legacyAnkiMedia,
        ownerId: name,
        label: 'media/$name',
        physicalBytes: size,
        fileCount: await _countFiles(dir.path),
        cleanupPolicy: hasOwner
            ? StorageCleanupPolicy.deleteSaga
            : StorageCleanupPolicy.confirmOnly,
        orphaned: !hasOwner,
      ));
    }

    // ── Official Anki: collection, catalog, media, backups ─────────────
    artifacts.addAll(await _scanOfficialDirectories());

    // ── Logs ────────────────────────────────────────────────────────────
    final logPath = LogCapture.instance.fileForDisplay?.path;
    artifacts.add(StorageArtifactReport(
      category: StorageArtifactCategory.logs,
      ownerId: '',
      label: 'diagnostics log',
      physicalBytes: await platform.fileSizeBytes(logPath),
      fileCount: logPath == null ? 0 : 1,
      cleanupPolicy: StorageCleanupPolicy.safeClear,
    ));

    final report = StorageInventoryReport(
      artifacts: artifacts,
      databaseWalBytes: walBytes,
      databaseShmBytes: shmBytes,
      freelistBytes: freelistBytes,
      aiCacheEntries: getIt.isRegistered<AiEngine>()
          ? getIt<AiEngine>().cacheStats().entries
          : 0,
      scannedAt: DateTime.now(),
    );
    trace.stop();
    PerformanceTrace.instance.record(
      feature: 'storage',
      operation: 'scan',
      duration: trace.elapsed,
      resultSize: report.artifacts.length,
    );
    return report;
  }

  /// File path of the database's main file, or null for in-memory
  /// connections (`PRAGMA database_list` reports an empty file).
  Future<String?> _mainDatabasePath(CourseDatabase db) async {
    final rows = await db.customSelect('PRAGMA database_list').get();
    for (final row in rows) {
      if ((row.data['name'] as String?) == 'main') {
        final file = row.data['file'] as String?;
        if (file != null && file.isNotEmpty) return file;
      }
    }
    return null;
  }

  Future<int> _freelistBytes(CourseDatabase db) async {
    final free = await db.customSelect('PRAGMA freelist_count').getSingle();
    final pageSize = await db.customSelect('PRAGMA page_size').getSingle();
    final freePages = free.data.values.first as int;
    final size = pageSize.data.values.first as int;
    return freePages * size;
  }

  /// Official storage lives under `<support>/official_anki/<profile>/`.
  /// Each profile directory is one artifact owned by its catalog: the
  /// collection and its catalog must be reclaimed through the official
  /// delete saga, not by deleting files directly.
  Future<List<StorageArtifactReport>> _scanOfficialDirectories() async {
    final support = await _applicationSupportPath();
    if (support == null) return const [];
    final root = Directory(p.join(support, 'official_anki'));
    if (!await root.exists()) return const [];
    final reports = <StorageArtifactReport>[];
    for (final profileDir in await _listSubdirectories(root.path)) {
      final profileId = p.basename(profileDir.path);
      var bytes = 0;
      var files = 0;
      const members = [
        'collection.anki2',
        'collection.media.db2',
        'official_catalog.sqlite',
        'engine.json',
      ];
      for (final member in members) {
        final path = p.join(profileDir.path, member);
        final size = await platform.fileSizeBytes(path);
        if (size > 0) {
          bytes += size;
          files++;
        }
      }
      final mediaSize = await platform
          .directorySizeBytes(p.join(profileDir.path, 'collection.media'));
      if (mediaSize > 0) {
        bytes += mediaSize;
        files += await _countFiles(p.join(profileDir.path, 'collection.media'));
      }
      final backupsSize =
          await platform.directorySizeBytes(p.join(profileDir.path, 'backups'));
      if (backupsSize > 0) {
        bytes += backupsSize;
        files += await _countFiles(p.join(profileDir.path, 'backups'));
      }
      final sourceCount = _officialSourceCount();
      reports.add(StorageArtifactReport(
        category: StorageArtifactCategory.officialAnki,
        ownerId: profileId,
        label: 'official_anki/$profileId'
            '${sourceCount != null ? " ($sourceCount sources)" : ""}',
        physicalBytes: bytes,
        fileCount: files,
        cleanupPolicy: StorageCleanupPolicy.deleteSaga,
      ));
    }
    return reports;
  }

  /// Source count from the already-initialized read-only catalog, when one
  /// is open. This is a best-effort label; the scan must not initialize
  /// engines or open databases just to describe disk usage.
  int? _officialSourceCount() {
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    if (catalog == null) return null;
    try {
      return OfficialAnkiSourceDao(catalog)
          .listSources('profile-default-01')
          .length;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _applicationSupportPath() async {
    try {
      return (await getApplicationSupportDirectory()).path;
    } catch (_) {
      return null;
    }
  }

  Future<List<Directory>> _listSubdirectories(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return const [];
    try {
      return await dir
          .list(followLinks: false)
          .where((entity) => entity is Directory)
          .cast<Directory>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<int> _countFiles(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    try {
      final entries = await dir
          .list(recursive: true, followLinks: false)
          .where((entity) => entity is File)
          .length;
      return entries;
    } catch (_) {
      return 0;
    }
  }
}
