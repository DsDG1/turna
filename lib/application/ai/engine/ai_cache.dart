// Dart imports:
import 'dart:convert';
import 'dart:collection';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';

// Flutter imports:
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Snapshot of cache counters (immutable view for telemetry).
///
/// Mirrors `ai_cache.py:AiCacheStats`.
class AiCacheStats {
  const AiCacheStats({
    this.hits = 0,
    this.misses = 0,
    this.entries = 0,
  });

  final int hits;
  final int misses;
  final int entries;

  @override
  String toString() =>
      'AiCacheStats(hits=$hits, misses=$misses, entries=$entries)';
}

/// In-memory LRU cache of AI chat-completion response bodies.
///
/// Ported from `tool/gui/src/backend/ai_cache.py:AiCache`.
///
/// Cache key = `sha256(model | serialised messages | response_format)`. The API
/// key is deliberately NOT part of the key material (so a key rotation does not
/// invalidate useful draft cache), and the cache never stores the API key or any
/// header - only the model's response body.
///
/// This is intentionally the only cache layer: responses are process-local,
/// bounded by [maxEntries], and disappear on restart.
@lazySingleton
class AiCache {
  /// Default capacity and on/off state for the production singleton. These
  /// are intentionally not constructor parameters: `injectable_generator`
  /// would otherwise try to resolve them via `gh<int>()` / `gh<bool>()`, and
  /// GetIt does not register primitive types.
  static const int defaultMaxEntries = 200;
  static const bool defaultEnabled = true;

  /// Production constructor used by `@lazySingleton`. Uses [defaultMaxEntries]
  /// and [defaultEnabled]; tests that need to tweak these should construct via
  /// [AiCache.forTest] instead.
  AiCache()
      : _maxEntries = defaultMaxEntries,
        _enabled = defaultEnabled && defaultMaxEntries > 0;

  /// Test-only constructor that lets specs vary [maxEntries] / [enabled]
  /// without exposing those knobs on the DI-injected production constructor.
  @visibleForTesting
  AiCache.forTest(
      {int maxEntries = defaultMaxEntries, bool enabled = defaultEnabled})
      : _maxEntries = maxEntries < 0 ? 0 : maxEntries,
        _enabled = enabled && maxEntries > 0;

  final int _maxEntries;
  bool _enabled;

  /// Insertion-ordered map; the head is the least-recently-used entry. Dart's
  /// `LinkedHashMap` preserves insertion order, so LRU touch = remove + re-add.
  final LinkedHashMap<String, Map<String, dynamic>> _mem = LinkedHashMap();

  bool get enabled => _enabled;
  int get maxEntries => _maxEntries;

  /// Toggle the cache at runtime. Disabling does NOT clear entries (mirrors
  /// `ai_cache.py:set_enabled`).
  void setEnabled(bool value) => _enabled = value && _maxEntries > 0;

  /// Stable SHA-256 key for a `(model, messages, response_format)` triple.
  ///
  /// Messages are serialised with sorted keys (mirrors Python's
  /// `sort_keys=True`) so reordering keys in a message dict does not
  /// invalidate the entry. The API key is intentionally excluded.
  static String makeKey(
    String model,
    List<Map<String, dynamic>> messages,
    Map<String, dynamic>? responseFormat,
  ) {
    final payload = _canonicalJson({
      'm': (model).trim(),
      'msg': messages,
      'rf': responseFormat,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  int _hits = 0;
  int _misses = 0;

  /// Return the cached body or `null` on miss / when disabled.
  Map<String, dynamic>? get(String key) {
    if (!_enabled) {
      _misses++;
      return null;
    }
    final entry = _mem.remove(key);
    if (entry != null) {
      _mem[key] = entry; // re-insert at the tail (most-recently-used)
      _hits++;
      return entry;
    }
    _misses++;
    return null;
  }

  /// Store [value] under [key]. No-op when disabled or when [value] is null.
  void put(String key, Map<String, dynamic>? value) {
    if (!_enabled || value == null) return;
    _putLocked(key, value);
  }

  /// Drop all process-local entries.
  void clear() {
    _mem.clear();
  }

  AiCacheStats stats() => AiCacheStats(
        hits: _hits,
        misses: _misses,
        entries: _mem.length,
      );

  void _putLocked(String key, Map<String, dynamic> value) {
    _mem[key] = value;
    while (_mem.length > _maxEntries) {
      _mem.remove(_mem.keys.first);
    }
  }
}

/// Canonical JSON encoding with sorted keys, mirroring Python's
/// `json.dumps(..., sort_keys=True, separators=(',', ':'))`. Used so the cache
/// key is stable regardless of map insertion order.
String _canonicalJson(Object? o) {
  if (o is Map) {
    final keys = o.keys.map((k) => k.toString()).toList()..sort();
    final parts = <String>[];
    for (final k in keys) {
      parts.add('${jsonEncode(k)}:${_canonicalJson(o[k])}');
    }
    return '{${parts.join(',')}}';
  } else if (o is List) {
    return '[${o.map(_canonicalJson).join(',')}]';
  } else {
    return jsonEncode(o);
  }
}
