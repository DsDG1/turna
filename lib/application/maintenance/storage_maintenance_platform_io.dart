import 'dart:io';

Future<int> directorySizeBytes(String path) async {
  final directory = Directory(path);
  if (!await directory.exists()) return 0;
  var bytes = 0;
  await for (final entity
      in directory.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      try {
        bytes += await entity.length();
      } catch (_) {}
    }
  }
  return bytes;
}

Future<int> fileSizeBytes(String? path) async {
  if (path == null || path.isEmpty) return 0;
  try {
    final file = File(path);
    return await file.exists() ? await file.length() : 0;
  } catch (_) {
    return 0;
  }
}
