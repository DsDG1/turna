// Dart imports:
import 'dart:io';

// Package imports:
import 'package:path_provider/path_provider.dart';

Future<String> getAnkiDocumentsPath() async {
  final directory = await getApplicationDocumentsDirectory();
  return directory.path;
}

bool ankiFileExists(String path) => File(path).existsSync();

bool ankiDirectoryExists(String path) => Directory(path).existsSync();

void ankiCreateDirectory(String path) {
  if (path.isEmpty) return;
  Directory(path).createSync(recursive: true);
}

void ankiCopyFile(String sourcePath, String targetPath) {
  File(sourcePath).copySync(targetPath);
}

void ankiDeleteDirectory(String path) => Directory(path).deleteSync(recursive: true);
