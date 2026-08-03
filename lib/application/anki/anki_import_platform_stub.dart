// Non-IO platform boundary for Anki import.
//
// The browser and unsupported Flutter targets can compile the importer and
// show a useful unsupported error without linking `dart:io`, `archive`, or
// the SQLite FFI package. The actual import remains available on IO targets.

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

String get ankiSystemTempPath => '';

bool ankiFileExists(String path) => false;

bool ankiDirectoryExists(String path) => false;

int ankiFileLength(String path) => 0;

List<int> ankiReadBytes(String path) => throw UnsupportedError(
      'Anki archive import requires an IO-capable platform.',
    );

String ankiReadString(String path) => throw UnsupportedError(
      'Anki archive import requires an IO-capable platform.',
    );

void ankiCreateDirectory(String path) {}

void ankiWriteBytes(String path, List<int> bytes) => throw UnsupportedError(
      'Anki archive import requires an IO-capable platform.',
    );

void ankiDeleteDirectory(String path) {}

List<AnkiArchiveEntry> decodeAnkiArchive(List<int> bytes) =>
    throw UnsupportedError(
      'Anki archive import requires an IO-capable platform.',
    );

AnkiSqlDatabase openAnkiDatabase(String path) => throw UnsupportedError(
      'Anki archive import requires an IO-capable platform.',
    );
