// Non-IO media boundary used by web and other unsupported targets.

// Project imports:
import 'package:turna/domain/audio/anki_media_delete_report.dart';

Future<String> getAnkiDocumentsPath() async => '';

bool ankiFileExists(String path) => false;

bool ankiDirectoryExists(String path) => false;

List<String> ankiListSubdirectories(String path) => const <String>[];

void ankiCreateDirectory(String path) {}

void ankiCopyFile(String sourcePath, String targetPath) =>
    throw UnsupportedError(
      'Anki media files require an IO-capable platform.',
    );

void ankiRenameDirectory(String sourcePath, String targetPath) =>
    throw UnsupportedError(
      'Anki media files require an IO-capable platform.',
    );

void ankiDeleteDirectory(String path) {}

AnkiMediaDeleteReport ankiDeleteDirectoryBestEffort(String path) =>
    const AnkiMediaDeleteReport();
