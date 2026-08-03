// Dart imports:
import 'dart:io';

// Package imports:
import 'package:archive/archive.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

class AnkiArchiveEntry {
  final bool isFile;
  final String name;
  final List<int> content;

  const AnkiArchiveEntry({
    required this.isFile,
    required this.name,
    this.content = const [],
  });
}

abstract class AnkiSqlDatabase {
  List<Map<String, Object?>> select(String sql);

  void dispose();
}

class _AnkiSqlDatabase implements AnkiSqlDatabase {
  final sql.Database _database;

  _AnkiSqlDatabase(this._database);

  @override
  List<Map<String, Object?>> select(String statement) => [
        for (final row in _database.select(statement))
          <String, Object?>{
            for (final column in row.keys) column: row[column],
          },
      ];

  @override
  void dispose() => _database.dispose();
}

String get ankiSystemTempPath => Directory.systemTemp.path;

bool ankiFileExists(String path) => File(path).existsSync();

bool ankiDirectoryExists(String path) => Directory(path).existsSync();

int ankiFileLength(String path) => File(path).lengthSync();

List<int> ankiReadBytes(String path) => File(path).readAsBytesSync();

String ankiReadString(String path) => File(path).readAsStringSync();

void ankiCreateDirectory(String path) {
  if (path.isEmpty) return;
  Directory(path).createSync(recursive: true);
}

void ankiWriteBytes(String path, List<int> bytes) =>
    File(path).writeAsBytesSync(bytes);

void ankiDeleteDirectory(String path) =>
    Directory(path).deleteSync(recursive: true);

List<AnkiArchiveEntry> decodeAnkiArchive(List<int> bytes) => [
      for (final entry in ZipDecoder().decodeBytes(bytes))
        AnkiArchiveEntry(
          isFile: entry.isFile,
          name: entry.name,
          content: entry.isFile
              ? List<int>.from(entry.content as List<int>)
              : const [],
        ),
    ];

AnkiSqlDatabase openAnkiDatabase(String path) =>
    _AnkiSqlDatabase(sql.sqlite3.open(path, mode: sql.OpenMode.readOnly));
