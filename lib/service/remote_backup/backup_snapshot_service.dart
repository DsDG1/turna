// Dart imports:
import 'dart:convert';
import 'dart:io';
import 'dart:math';

// Package imports:
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

// Project imports:
import 'package:turna/service/remote_backup/archive_io.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_sqlite.dart';
import 'package:turna/application/backup/backup_manifest_policy.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/service/remote_backup/backup_manifest.dart';
import 'package:turna/service/remote_backup/remote_backup_busy_gate.dart';

/// Coarse snapshot stages surfaced to the backup UI.
enum BackupSnapshotPhase {
  collectingPrefs,
  snapshottingCourseDb,
  snapshottingOfficialDbs,
  hashingMedia,
  packingArchive,
}

/// Result of a successful local snapshot: the archive ready for upload plus
/// the deduplicated set of media objects the caller may still need to push.
class BackupSnapshot {
  const BackupSnapshot({
    required this.backupId,
    required this.coreZip,
    required this.coreZipSha256,
    required this.meta,
    required this.mediaManifest,
    required this.mediaObjects,
  });

  final String backupId;
  final File coreZip;
  final String coreZipSha256;
  final BackupArchiveMeta meta;

  /// logical media path (e.g. `anki_media/<id>/a.mp3`) → hash + size.
  final Map<String, MediaManifestEntry> mediaManifest;

  /// content hash → path of the verified snapshot copy under the staging
  /// `objects/` directory, deduplicated upload set. Uploads always read
  /// these copies, never the live media files.
  final Map<String, String> mediaObjects;

  int get coreZipBytes => coreZip.lengthSync();
}

/// Which prefs keys travel inside a backup archive is decided solely by
/// [BackupManifestPolicy] — the same single source of truth the local JSON
/// export uses, so both paths carry an identical settings/progress set and
/// can never drift apart again. Device-local keys (remote backup config /
/// device id, system health events, per-day Anki counters) and credentials
/// are structurally excluded by the policy.

/// Builds a consistent local snapshot of all user data into a staging
/// directory:
///
/// - prefs: allowlisted SharedPreferences keys (secrets stripped);
/// - `course.db`: drift `VACUUM INTO` — an online, per-database-consistent
///   copy, no close needed;
/// - official Anki dbs (`collection.anki2`, `official_catalog.sqlite`,
///   `collection.media.db2`): read-only secondary connections + `VACUUM INTO`
///   (works on a live WAL database, mirrors the native bridge's
///   create_backup safety without needing engine coordination);
/// - media: content-hashed files under `anki_media/` and
///   `collection.media/`, listed in `media_manifest.json` (the hashes double
///   as remote object names).
///
/// Everything is packed into `core.zip` (streamed — never fully in memory)
/// plus a `SHA256SUMS` manifest, mirroring the p5c physical backup format.
class BackupSnapshotService {
  BackupSnapshotService({
    required CourseDatabase db,
    required PackageInfo packageInfo,
    Directory? officialProfileRoot,
    Directory? legacyMediaRoot,
  })  : _db = db,
        _packageInfo = packageInfo,
        _officialProfileRoot = officialProfileRoot,
        _legacyMediaRoot = legacyMediaRoot;

  final CourseDatabase _db;
  final PackageInfo _packageInfo;
  Directory? _officialProfileRoot;
  Directory? _legacyMediaRoot;

  Future<Directory> _resolveProfileRoot() async =>
      _officialProfileRoot ??= Directory(p.join(
          (await getApplicationSupportDirectory()).path,
          'official_anki',
          'default'));

  Future<Directory> _resolveLegacyMediaRoot() async =>
      _legacyMediaRoot ??= Directory(p.join(
          (await getApplicationDocumentsDirectory()).path, 'anki_media'));

  /// Creates a fresh [stagingDir] (wiped if present) and builds the snapshot
  /// inside it. [onPhase] / [onMediaProgress] drive the backup UI.
  /// [busyCheck] is evaluated before every phase: a study activity that
  /// started despite the caller's hold aborts the build with
  /// [RemoteBackupBusyException] instead of packing an inconsistent archive
  /// (plan P0). [copyImpl] is a test seam for the media copy step.
  Future<BackupSnapshot> build({
    required Directory stagingDir,
    bool includeMedia = true,
    void Function(BackupSnapshotPhase phase)? onPhase,
    void Function(int hashed, int total)? onMediaProgress,
    void Function()? busyCheck,
    Future<void> Function(File source, File dest)? copyImpl,
  }) async {
    void guard() => busyCheck?.call();
    guard();
    onPhase?.call(BackupSnapshotPhase.collectingPrefs);
    if (await stagingDir.exists()) {
      await stagingDir.delete(recursive: true);
    }
    await stagingDir.create(recursive: true);

    final backupId = _mintBackupId();
    final prefsMap = await _collectPrefs();
    await _writeJson(stagingDir, 'prefs.json', prefsMap);

    guard();
    onPhase?.call(BackupSnapshotPhase.snapshottingCourseDb);
    await _vacuumInto(_db, p.join(stagingDir.path, 'course.db'));

    guard();
    onPhase?.call(BackupSnapshotPhase.snapshottingOfficialDbs);
    final profileRoot = await _resolveProfileRoot();
    final collectionFile = await _vacuumFileIfExists(
        p.join(profileRoot.path, 'collection.anki2'),
        p.join(stagingDir.path, 'collection.anki2'));
    final catalogFile = await _vacuumFileIfExists(
        p.join(profileRoot.path, 'official_catalog.sqlite'),
        p.join(stagingDir.path, 'official_catalog.sqlite'));
    final mediaDbFile = await _vacuumFileIfExists(
        p.join(profileRoot.path, 'collection.media.db2'),
        p.join(stagingDir.path, 'collection.media.db2'));

    final mediaManifest = <String, MediaManifestEntry>{};
    final mediaObjects = <String, String>{};
    if (includeMedia) {
      guard();
      onPhase?.call(BackupSnapshotPhase.hashingMedia);
      final objectsDir = Directory(p.join(stagingDir.path, 'objects'))
        ..createSync(recursive: true);
      await _scanMedia(
        await _resolveLegacyMediaRoot(),
        'anki_media/',
        objectsDir,
        mediaManifest,
        mediaObjects,
        onMediaProgress,
        copyImpl ?? _defaultCopy,
      );
      await _scanMedia(
        Directory(p.join(profileRoot.path, 'collection.media')),
        'official/collection.media/',
        objectsDir,
        mediaManifest,
        mediaObjects,
        onMediaProgress,
        copyImpl ?? _defaultCopy,
      );
    }
    await _writeJson(
        stagingDir, 'media_manifest.json', _encodeMediaManifest(mediaManifest));

    final meta = BackupArchiveMeta(
      appVersion: _packageInfo.version,
      buildNumber: _packageInfo.buildNumber,
      platform: Platform.operatingSystem,
      deviceLabel: Platform.operatingSystem,
      driftSchema: _db.schemaVersion,
      catalogSchema: kOfficialAnkiCatalogSchemaVersion,
      createdAtUtc: DateTime.now().toUtc(),
      hasCollection: collectionFile != null,
      hasCatalog: catalogFile != null,
      hasMediaDb: mediaDbFile != null,
      prefsCount: prefsMap.length,
    );
    await _writeJson(stagingDir, 'meta.json', meta.toJson());

    final entries = <String>[
      'prefs.json',
      'course.db',
      if (collectionFile != null) 'collection.anki2',
      if (catalogFile != null) 'official_catalog.sqlite',
      if (mediaDbFile != null) 'collection.media.db2',
      'media_manifest.json',
      'meta.json',
    ];
    await _writeSha256Sums(stagingDir, entries);
    entries.add('SHA256SUMS');

    guard();
    onPhase?.call(BackupSnapshotPhase.packingArchive);
    final coreZip = File(p.join(stagingDir.path, 'core.zip'));
    await _packZip(stagingDir, entries, coreZip);

    return BackupSnapshot(
      backupId: backupId,
      coreZip: coreZip,
      coreZipSha256: archiveFileSha256(coreZip.path),
      meta: meta,
      mediaManifest: mediaManifest,
      mediaObjects: mediaObjects,
    );
  }

  String _mintBackupId() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final suffix = List.generate(
      4,
      (_) => _idAlphabet[_random.nextInt(_idAlphabet.length)],
    ).join();
    return 'bk-$millis-$suffix';
  }

  static const _idAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static final _random = Random();

  Future<Map<String, Object?>> _collectPrefs() async {
    // streaming_shared_preferences wraps the SharedPreferences singleton,
    // so getInstance() here sees the same store (already initialized).
    final sp = await SharedPreferences.getInstance();
    final out = <String, Object?>{};
    for (final key in sp.getKeys()) {
      // Single policy object shared with the local export path — secrets are
      // stripped at this serialization boundary.
      final sanitized = BackupManifestPolicy.sanitizeForSerialization(
        key,
        sp.get(key),
      );
      if (sanitized != null) out[key] = sanitized;
    }
    return out;
  }

  /// Online-consistent copy of the live drift database.
  Future<File> _vacuumInto(CourseDatabase db, String targetPath) async {
    await db.customStatement("VACUUM INTO '${_sqlLiteral(targetPath)}'");
    final file = File(targetPath);
    if (!await file.exists() || await file.length() == 0) {
      throw StateError('VACUUM INTO produced no output for course.db');
    }
    return file;
  }

  /// VACUUM INTO for dbs the app does not own through drift. Absent or empty
  /// sources (engine never ran) restore as "not present", not as garbage.
  Future<File?> _vacuumFileIfExists(String sourcePath, String targetPath) =>
      _withReadOnlyDb(sourcePath, (db) async {
        db.execute("VACUUM INTO '${_sqlLiteral(targetPath)}'");
        final file = File(targetPath);
        if (!await file.exists() || await file.length() == 0) {
          throw StateError('VACUUM INTO produced no output for $sourcePath');
        }
        return file;
      });

  Future<T?> _withReadOnlyDb<T>(
      String path, Future<T> Function(sql.Database db) action) async {
    final source = File(path);
    if (!await source.exists() || await source.length() == 0) return null;
    ensureOfficialAnkiSqlite();
    final db = sql.sqlite3.open(path, mode: sql.OpenMode.readOnly);
    try {
      return await action(db);
    } finally {
      db.dispose();
    }
  }

  static Future<void> _defaultCopy(File source, File dest) async {
    await source.copy(dest.path);
  }

  /// Lists every media file, captures a verified copy of each into the
  /// staging `objects/` directory (content-addressed by SHA-256), and
  /// records the manifest entries. Copies are what later get uploaded —
  /// the live file changing between hashing and transfer can no longer
  /// desynchronize a remote object from its content-addressed name
  /// (plan P0).
  Future<void> _scanMedia(
    Directory root,
    String logicalPrefix,
    Directory objectsDir,
    Map<String, MediaManifestEntry> manifest,
    Map<String, String> objects,
    void Function(int hashed, int total)? onProgress,
    Future<void> Function(File source, File dest) copyImpl,
  ) async {
    if (!await root.exists()) return;
    final files = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) files.add(entity);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    var hashed = 0;
    for (final file in files) {
      final relative =
          p.relative(file.path, from: root.path).replaceAll('\\', '/');
      final sha = await _captureVerifiedCopy(file, objectsDir, copyImpl);
      objects.putIfAbsent(sha, () => p.join(objectsDir.path, sha));
      manifest['$logicalPrefix$relative'] = MediaManifestEntry(
          sha256: sha, bytes: File(objects[sha]!).lengthSync());
      onProgress?.call(++hashed, files.length);
    }
  }

  /// Copies [source] into [objectsDir] under its content hash and verifies
  /// the copy byte-for-byte. If the source mutates mid-copy the digests
  /// disagree and one retry re-captures the (now stable) content; a second
  /// disagreement means the file is being written right now — the snapshot
  /// aborts rather than shipping a torn object.
  Future<String> _captureVerifiedCopy(
    File source,
    Directory objectsDir,
    Future<void> Function(File source, File dest) copyImpl,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      final sha = archiveFileSha256(source.path);
      final dest = File(p.join(objectsDir.path, sha));
      await copyImpl(source, dest);
      if (archiveFileSha256(dest.path) == sha) return sha;
      lastError = StateError('媒体文件在快照期间持续变化: ${p.basename(source.path)}');
    }
    throw lastError!;
  }

  Map<String, dynamic> _encodeMediaManifest(
          Map<String, MediaManifestEntry> manifest) =>
      <String, dynamic>{
        for (final entry in manifest.entries) entry.key: entry.value.toJson(),
      };

  Future<void> _writeSha256Sums(Directory dir, List<String> names) async {
    final lines = <String>[];
    for (final name in names) {
      final digest = archiveFileSha256(p.join(dir.path, name));
      lines.add('$digest  $name');
    }
    await File(p.join(dir.path, 'SHA256SUMS'))
        .writeAsString('${lines.join('\n')}\n', flush: true);
  }

  /// Streams the staged files into a zip — no entry is fully buffered except
  /// the small JSON documents.
  Future<void> _packZip(Directory dir, List<String> names, File target) async {
    final output = OutputFileStream(target.path);
    final encoder = ZipEncoder()..startEncode(output);
    try {
      for (final name in names) {
        final path = p.join(dir.path, name);
        if (_smallTextEntries.contains(name)) {
          encoder.add(ArchiveFile.bytes(name, await File(path).readAsBytes()));
        } else {
          final stream = InputFileStream(path);
          try {
            encoder.add(ArchiveFile.stream(name, stream));
          } finally {
            await stream.close();
          }
        }
      }
      encoder.endEncode();
    } finally {
      await output.close();
    }
    if (!await target.exists() || await target.length() == 0) {
      throw StateError('core.zip packing produced no output');
    }
  }

  static const _smallTextEntries = <String>{
    'prefs.json',
    'media_manifest.json',
    'meta.json',
    'SHA256SUMS',
  };

  String _sqlLiteral(String path) => path.replaceAll("'", "''");

  Future<void> _writeJson(Directory dir, String name, Object? payload) async {
    await File(p.join(dir.path, name)).writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        flush: true);
  }
}
