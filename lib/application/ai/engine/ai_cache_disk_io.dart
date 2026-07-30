// Dart imports:
import 'dart:convert';
import 'dart:io';

/// Persistent backing store for [AiCache], using the local file system.
///
/// This is the native (vm / Android / iOS / OHOS / desktop) implementation. A
/// no-op web twin lives in `ai_cache_disk_web.dart` and is selected via a
/// conditional import in `ai_cache.dart`, so the cache compiles and runs on
/// every target - the disk mirror simply does nothing on web.
///
/// Each entry is stored as `<dir>/<sha256>.json` containing only the model's
/// response body (never the API key or any header - per
/// `ai_cache.py` §"Security notes"). Writes are atomic via a `.tmp` file plus
/// `File.rename`, mirroring `ai_cache.py:_save_to_disk` (`os.replace`).
class DiskCacheStore {
  DiskCacheStore(this.dir) {
    final d = Directory(dir);
    if (!d.existsSync()) {
      d.createSync(recursive: true);
    }
  }

  final String dir;

  File _file(String key) => File('$dir/$key.json');

  /// Read a cached body by key, or `null` when absent / corrupt. Corrupt reads
  /// are swallowed (counted as a disk error by the caller) rather than thrown.
  Map<String, dynamic>? read(String key) {
    final f = _file(key);
    if (!f.existsSync()) return null;
    try {
      final data = jsonDecode(f.readAsStringSync(encoding: utf8));
      if (data is Map<String, dynamic>) return data;
    } catch (_) {
      // Corrupt file - treat as a miss; caller tallies disk_errors.
    }
    return null;
  }

  /// Atomically write [value] under [key]. Returns `false` on I/O failure so
  /// the caller can bump its disk-error counter without throwing.
  bool write(String key, Map<String, dynamic> value) {
    final target = _file(key);
    final tmp = File('$dir/$key.json.tmp');
    try {
      tmp.writeAsStringSync(
        jsonEncode(value),
        encoding: utf8,
        flush: true,
      );
      // On Windows, `renameSync` fails if the target exists; delete first.
      if (target.existsSync()) target.deleteSync();
      tmp.renameSync(target.path);
      return true;
    } catch (_) {
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } catch (_) {
          // Best-effort cleanup of the temp file.
        }
      }
      return false;
    }
  }

  /// Remove every `*.json` cache file. Best-effort; returns `false` if any
  /// deletion fails so the caller can tally disk errors.
  bool clear() {
    var ok = true;
    try {
      for (final f in Directory(dir).listSync()) {
        if (f is! File) continue;
        if (!f.path.endsWith('.json')) continue;
        try {
          f.deleteSync();
        } catch (_) {
          ok = false;
        }
      }
    } catch (_) {
      ok = false;
    }
    return ok;
  }
}
