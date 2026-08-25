// Dart imports:
import 'dart:io';

// Package imports:
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:turna/domain/audio/anki_media_delete_report.dart';

Future<String> getAnkiDocumentsPath() async {
  final directory = await getApplicationDocumentsDirectory();
  return directory.path;
}

bool ankiFileExists(String path) => File(path).existsSync();

bool ankiDirectoryExists(String path) => Directory(path).existsSync();

List<String> ankiListSubdirectories(String path) => Directory(path)
    .listSync(followLinks: false)
    .whereType<Directory>()
    .map((dir) => dir.path)
    .toList();

void ankiCreateDirectory(String path) {
  if (path.isEmpty) return;
  Directory(path).createSync(recursive: true);
}

void ankiCopyFile(String sourcePath, String targetPath) {
  File(sourcePath).copySync(targetPath);
}

void ankiRenameDirectory(String sourcePath, String targetPath) {
  Directory(sourcePath).renameSync(targetPath);
}

void ankiDeleteDirectory(String path) =>
    Directory(path).deleteSync(recursive: true);

/// Delete [path] file by file so one locked file cannot abort the whole
/// pass. Directories are removed bottom-up afterwards; a directory that
/// still holds locked files stays on disk and is reported — the orphan
/// sweep retries it on the next app start.
AnkiMediaDeleteReport ankiDeleteDirectoryBestEffort(String path) {
  if (path.isEmpty) return const AnkiMediaDeleteReport();
  final root = Directory(path);
  if (!root.existsSync()) return const AnkiMediaDeleteReport();

  final entities = root.listSync(recursive: true, followLinks: false);
  var deleted = 0;
  final remaining = <String>[];
  for (final entity in entities) {
    if (entity is! File && entity is! Link) continue;
    try {
      entity.deleteSync();
      deleted++;
    } on FileSystemException {
      remaining.add(entity.path);
    }
  }

  // Longer paths are deeper in the tree, so a length sort visits children
  // before their parents without building a real tree.
  final dirs = entities.whereType<Directory>().toList()
    ..sort((a, b) => b.path.length.compareTo(a.path.length));
  final remainingDirectories = <String>[];
  for (final dir in [...dirs, root]) {
    try {
      dir.deleteSync();
    } on FileSystemException {
      // Still exists (locked file, permissions, or a directory handle) —
      // report it even if every child file happened to be removed.
    }
    if (dir.existsSync()) {
      remainingDirectories.add(dir.path);
    }
  }

  return AnkiMediaDeleteReport(
    deletedFiles: deleted,
    remainingFiles: remaining.length,
    remainingPaths: remaining,
    remainingDirectories: remainingDirectories,
  );
}
