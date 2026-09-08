// Dart imports:
import 'dart:io';

// Package imports:
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
