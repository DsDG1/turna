// Dart imports:
import 'dart:io';

// Package imports:
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

// Project imports:
import 'package:turna/core/logger.dart';
import 'package:turna/data/course_database.dart';

/// Best-effort pre-migration safety copy of the course DB (plan §9 R1).
///
/// Must run BEFORE the drift [CourseDatabase] is constructed — drift opens
/// lazily, so at that point nothing else holds the file. When the on-disk
/// `user_version` is behind [CourseDatabase.kSchemaVersion], the file is
/// snapshotted next to itself as `course.db.v<version>.bak` via
/// `VACUUM INTO`: an online, internally consistent copy that also folds in
/// committed WAL frames (a plain `File.copy` can miss those).
///
/// Failures never block startup — the migration already ran unbacked before
/// this existed, so logging and continuing is strictly no worse.
Future<File?> backupCourseDbBeforeMigration(File dbFile) async {
  try {
    if (!await dbFile.exists()) return null;
    final raw = sqlite3.sqlite3.open(dbFile.path);
    try {
      final version = raw.select('PRAGMA user_version').first['user_version']
          as int;
      if (version <= 0 || version >= CourseDatabase.kSchemaVersion) {
        return null;
      }
      final target = File('${dbFile.path}.v$version.bak');
      if (await target.exists()) {
        await target.delete();
      }
      final literal = target.path.replaceAll("'", "''");
      raw.execute("VACUUM INTO '$literal'");
      logger.i(
        'Course DB pre-migration backup written: ${target.path} (v$version)',
      );
      return target;
    } finally {
      raw.dispose();
    }
  } catch (error) {
    logger.w('Course DB pre-migration backup failed (continuing): $error');
    return null;
  }
}

/// Last-resort recovery when opening/migrating the course DB fails: copy the
/// NEWEST `course.db.v<version>.bak` snapshot over the broken file and let
/// the caller retry the open (the restored file carries an older
/// `user_version`, so the migration chain reruns on it).
///
/// Trade-off, accepted deliberately: when no same-version snapshot exists
/// this rolls the DB back to an older one — losing recent derived data beats
/// a permanent startup crash loop, and the course DB is a reseedable cache
/// while `srs_states` / `review_events` snapshots at least predate the
/// failure. Returns the restored backup file, or null when no backup exists
/// (the caller then rethrows the original error).
Future<File?> restoreCourseDbFromBackup(File dbFile) async {
  try {
    final dir = dbFile.parent;
    final prefix = p.basenameWithoutExtension(dbFile.path); // "course"
    final candidates = <int, File>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      // course.db.v24.bak / course.db.v25.bak
      final match =
          RegExp('^${RegExp.escape(prefix)}\\.db\\.v(\\d+)\\.bak\$')
              .firstMatch(name);
      if (match == null) continue;
      final version = int.parse(match.group(1)!);
      final existing = candidates[version];
      if (existing == null || entity.path != existing.path) {
        candidates[version] = entity;
      }
    }
    if (candidates.isEmpty) return null;
    final newestVersion = candidates.keys.reduce((a, b) => a > b ? a : b);
    final backup = candidates[newestVersion]!;

    // Drop the broken database together with any WAL/SHM sidecars so the
    // restored file opens clean.
    for (final suffix in const ['', '-wal', '-shm']) {
      final sidecar = File('${dbFile.path}$suffix');
      if (await sidecar.exists()) {
        await sidecar.delete();
      }
    }
    await backup.copy(dbFile.path);
    logger.w(
      'Course DB restored from pre-migration backup '
      '${backup.path} (v$newestVersion) after open/migrate failure',
    );
    return backup;
  } catch (error) {
    logger.w('Course DB restore-from-backup failed: $error');
    return null;
  }
}
