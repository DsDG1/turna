import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-disk media for imported `.turnapack` courses.
///
/// Pack JSON references files as `media/dog1.jpg`. Import rewrites those to
/// `turnapack://<code>/dog1.jpg`, stored under
/// `imported_courses/<code>/media/`.
class CoursePackMedia {
  CoursePackMedia._();

  static const String scheme = 'turnapack://';
  static const int maxZipBytes = 80 * 1024 * 1024;
  static const int maxUncompressedBytes = 200 * 1024 * 1024;
  static const int maxSingleFileBytes = 15 * 1024 * 1024;

  static const Set<String> allowedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.mp3',
    '.ogg',
    '.wav',
    '.m4a',
    '.aac',
    '.opus',
  };

  @visibleForTesting
  static Directory? debugPersistRoot;

  static bool isPackAsset(String? path) =>
      path != null && path.startsWith(scheme);

  static bool isMediaRelative(String path) {
    final n = path.replaceAll('\\', '/');
    return n == 'media' || n.startsWith('media/');
  }

  static String refFor(String code, String relative) {
    final rel = _safeRelative(relative);
    return '$scheme$code/$rel';
  }

  static String rewrite(String raw, String code) {
    final n = raw.trim().replaceAll('\\', '/');
    if (n.startsWith(scheme)) return n;
    if (n.startsWith('media/')) {
      return refFor(code, n.substring('media/'.length));
    }
    return raw;
  }

  static Future<Directory> persistRoot({Directory? override}) async {
    if (override != null) return override;
    if (debugPersistRoot != null) return debugPersistRoot!;
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'imported_courses'));
  }

  static Future<Directory> mediaDirectory(
    String code, {
    Directory? persist,
  }) async {
    final root = await persistRoot(override: persist);
    return Directory(p.join(root.path, code, 'media'));
  }

  static Future<String?> resolveFile(
    String assetPath, {
    Directory? persist,
  }) async {
    if (!isPackAsset(assetPath)) return null;
    final body = assetPath.substring(scheme.length);
    final slash = body.indexOf('/');
    if (slash <= 0 || slash == body.length - 1) return null;
    final code = body.substring(0, slash);
    final relative = _safeRelative(body.substring(slash + 1));
    if (relative.isEmpty) return null;
    final dir = await mediaDirectory(code, persist: persist);
    final full = p.normalize(p.join(dir.path, relative));
    if (!_isWithin(dir.path, full)) return null;
    final file = File(full);
    return file.existsSync() ? file.path : null;
  }

  static Future<void> deleteExtractedMedia(
    String code, {
    Directory? persist,
  }) async {
    final dir = await mediaDirectory(code, persist: persist);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }

  static bool isAllowedMediaName(String relative) {
    final rel = _safeRelative(relative);
    if (rel.isEmpty) return false;
    final ext = p.extension(rel).toLowerCase();
    return allowedExtensions.contains(ext);
  }

  static String _safeRelative(String relative) {
    var n = relative.replaceAll('\\', '/').replaceAll('\x00', '');
    while (n.startsWith('/')) {
      n = n.substring(1);
    }
    if (n.startsWith('media/')) n = n.substring('media/'.length);
    if (n.contains('..') || n.contains(':') || n.startsWith('~')) {
      return '';
    }
    return n;
  }

  static bool _isWithin(String root, String candidate) {
    final rootPath = p.normalize(root);
    final candidatePath = p.normalize(candidate);
    if (p.equals(rootPath, candidatePath)) return true;
    final prefix =
        rootPath.endsWith(p.separator) ? rootPath : '$rootPath${p.separator}';
    return candidatePath.startsWith(prefix);
  }

  static bool looksLikeZip(List<int> bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07);
  }
}
