/// No-op web twin of [DiskCacheStore] (see `ai_cache_disk_io.dart`).
///
/// Web targets have no local file system, so the disk mirror is a no-op here.
/// Selected via the conditional import in `ai_cache.dart`; the public API
/// matches [DiskCacheStore] exactly so the cache code is platform-agnostic.
class DiskCacheStore {
  DiskCacheStore(this.dir);

  final String dir;

  Map<String, dynamic>? read(String key) => null;

  bool write(String key, Map<String, dynamic> value) => false;

  bool clear() => true;
}
