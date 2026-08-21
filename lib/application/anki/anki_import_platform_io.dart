// Dart imports:
import 'dart:io';
import 'dart:typed_data';

// Package imports:
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

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

String ankiReadString(String path) => File(path).readAsStringSync();

void ankiCreateDirectory(String path) {
  if (path.isEmpty) return;
  Directory(path).createSync(recursive: true);
}

void ankiDeleteDirectory(String path) =>
    Directory(path).deleteSync(recursive: true);

/// Computes the SHA-256 of [path] in fixed-size chunks so hashing a large
/// `.apkg` never holds the whole archive in memory.
String ankiHashFileSha256(String path) {
  const chunkSize = 1024 * 1024;
  final digestSink = _DigestSink();
  final sink = sha256.startChunkedConversion(digestSink);
  final file = File(path).openSync();
  try {
    final buffer = Uint8List(chunkSize);
    while (true) {
      final read = file.readIntoSync(buffer, 0, chunkSize);
      if (read <= 0) break;
      sink.add(Uint8List.sublistView(buffer, 0, read));
    }
  } finally {
    file.closeSync();
  }
  sink.close();
  return digestSink.digest.toString();
}

/// Extracts a ZIP archive into [destDir] by streaming each entry straight to
/// disk, the same pattern `package:archive`'s own `extractFileToDisk` uses.
/// Neither the archive bytes nor any entry's content is fully held in memory,
/// so multi-hundred-megabyte decks extract with flat memory use.
///
/// [resolveEntryPath] maps an archive entry name to a path relative to
/// [destDir]; it may throw to abort extraction (unsafe-name rejection).
/// [onEntry] runs just before an entry is written, receiving the entry's
/// declared uncompressed size, so callers can enforce size caps before any
/// data is written to disk.
Future<void> ankiExtractArchiveToDisk(
  String archivePath,
  String destDir, {
  required String Function(String entryName) resolveEntryPath,
  required void Function(String entryName, int uncompressedSize) onEntry,
}) async {
  final input = InputFileStream(archivePath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      onEntry(entry.name, entry.size);
      final outputPath = p.join(destDir, resolveEntryPath(entry.name));
      ankiCreateDirectory(p.dirname(outputPath));
      final output = OutputFileStream(outputPath);
      try {
        entry.writeContent(output);
      } finally {
        await output.close();
      }
    }
  } finally {
    await input.close();
  }
}

AnkiSqlDatabase openAnkiDatabase(String path) =>
    _AnkiSqlDatabase(sql.sqlite3.open(path, mode: sql.OpenMode.readOnly));

/// Collects the single digest emitted by [Hash.startChunkedConversion].
class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get digest => _digest ?? (throw StateError('no digest collected'));

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}
