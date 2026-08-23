import 'package:flutter/painting.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/playground/playground_index_cache.dart';
import 'package:turna/application/review_dashboard/review_dashboard_repository.dart';
import 'package:turna/di/injection.dart';

class CacheFootprint {
  const CacheFootprint({
    required this.owner,
    required this.entries,
    required this.estimatedBytes,
  });

  final String owner;
  final int entries;
  final int? estimatedBytes;
}

class CacheClearResult {
  const CacheClearResult({required this.owner, required this.clearedEntries});

  final String owner;
  final int clearedEntries;
}

abstract interface class CacheDiagnosticsAdapter {
  String get owner;
  Future<CacheFootprint> inspect();
  Future<CacheClearResult> clearRegenerable();
}

class CacheDiagnosticsRegistry {
  CacheDiagnosticsRegistry(Iterable<CacheDiagnosticsAdapter> adapters)
      : _adapters = List.unmodifiable(adapters);

  factory CacheDiagnosticsRegistry.production() {
    return CacheDiagnosticsRegistry([
      if (getIt.isRegistered<AiEngine>()) _AiCacheAdapter(getIt<AiEngine>()),
      _PlaygroundCacheAdapter(PlaygroundIndexCache.instance),
      if (getIt.isRegistered<ReviewDashboardRepository>())
        _DashboardCacheAdapter(getIt<ReviewDashboardRepository>()),
      _FlutterImageCacheAdapter(),
    ]);
  }

  final List<CacheDiagnosticsAdapter> _adapters;

  /// Registered adapters in construction order. Exposed so a coordinator
  /// (ClearRegenerableCachesCommand) can run each owner isolated and keep
  /// per-owner results instead of an all-or-nothing Future.wait.
  List<CacheDiagnosticsAdapter> get adapters => List.unmodifiable(_adapters);

  Future<List<CacheFootprint>> inspectAll() =>
      Future.wait(_adapters.map((adapter) => adapter.inspect()));

  Future<List<CacheClearResult>> clearRegenerable() =>
      Future.wait(_adapters.map((adapter) => adapter.clearRegenerable()));
}

class _AiCacheAdapter implements CacheDiagnosticsAdapter {
  _AiCacheAdapter(this.engine);
  final AiEngine engine;
  @override
  String get owner => 'ai.responseCache';
  @override
  Future<CacheFootprint> inspect() async => CacheFootprint(
        owner: owner,
        entries: engine.cacheStats().entries,
        estimatedBytes: null,
      );
  @override
  Future<CacheClearResult> clearRegenerable() async {
    final before = engine.cacheStats().entries;
    engine.clearCache();
    return CacheClearResult(owner: owner, clearedEntries: before);
  }
}

class _PlaygroundCacheAdapter implements CacheDiagnosticsAdapter {
  _PlaygroundCacheAdapter(this.cache);
  final PlaygroundIndexCache cache;
  @override
  String get owner => 'playground.revisionCache';
  @override
  Future<CacheFootprint> inspect() async => CacheFootprint(
        owner: owner,
        entries: cache.entryCount,
        estimatedBytes: null,
      );
  @override
  Future<CacheClearResult> clearRegenerable() async {
    final before = cache.entryCount;
    cache.clear();
    return CacheClearResult(owner: owner, clearedEntries: before);
  }
}

class _DashboardCacheAdapter implements CacheDiagnosticsAdapter {
  _DashboardCacheAdapter(this.repository);
  final ReviewDashboardRepository repository;
  @override
  String get owner => 'review.dashboardSnapshot';
  @override
  Future<CacheFootprint> inspect() async => CacheFootprint(
        owner: owner,
        entries: repository.cachedSnapshot == null ? 0 : 1,
        estimatedBytes: null,
      );
  @override
  Future<CacheClearResult> clearRegenerable() async {
    final before = repository.cachedSnapshot == null ? 0 : 1;
    repository.invalidate();
    return CacheClearResult(owner: owner, clearedEntries: before);
  }
}

class _FlutterImageCacheAdapter implements CacheDiagnosticsAdapter {
  @override
  String get owner => 'flutter.imageCache';
  @override
  Future<CacheFootprint> inspect() async {
    final cache = PaintingBinding.instance.imageCache;
    return CacheFootprint(
      owner: owner,
      entries: cache.currentSize,
      estimatedBytes: cache.currentSizeBytes,
    );
  }

  @override
  Future<CacheClearResult> clearRegenerable() async {
    final cache = PaintingBinding.instance.imageCache;
    final before = cache.currentSize;
    cache.clear();
    cache.clearLiveImages();
    return CacheClearResult(owner: owner, clearedEntries: before);
  }
}
