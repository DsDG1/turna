// Non-IO media boundary used by web and other unsupported targets.

Future<String> getAnkiDocumentsPath() async => '';

bool ankiFileExists(String path) => false;

bool ankiDirectoryExists(String path) => false;

void ankiCreateDirectory(String path) {}

void ankiCopyFile(String sourcePath, String targetPath) => throw UnsupportedError(
      'Anki media files require an IO-capable platform.',
    );

void ankiDeleteDirectory(String path) {}
