// Non-IO platform boundary for Anki import.
//
// The browser and unsupported Flutter targets can compile the importer and
// show a useful unsupported error without linking `dart:io`, `archive`, or
// the SQLite FFI package. The actual import remains available on IO targets.

abstract class AnkiSqlDatabase {
  List<Map<String, Object?>> select(String sql);

  void dispose();
}

String get ankiSystemTempPath => '';

bool ankiFileExists(String path) => false;

bool ankiDirectoryExists(String path) => false;

int ankiFileLength(String path) => 0;

String ankiReadString(String path) => throw UnsupportedError(
      'Anki archive import requires an IO-capable platform.',
    );

void ankiCreateDirectory(String path) {}

void ankiDeleteDirectory(String path) {}

String ankiHashFileSha256(String path) => throw UnsupportedError(
      'Anki archive import requires an IO-capable platform.',
    );

Future<void> ankiExtractArchiveToDisk(
  String archivePath,
  String destDir, {
  required String Function(String entryName) resolveEntryPath,
  required void Function(String entryName, int uncompressedSize) onEntry,
}) async =>
    throw UnsupportedError(
      'Anki archive import requires an IO-capable platform.',
    );

AnkiSqlDatabase openAnkiDatabase(String path) => throw UnsupportedError(
      'Anki archive import requires an IO-capable platform.',
    );
