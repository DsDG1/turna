// Dart imports:
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';

// Flutter imports:
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

/// Snapshot of cache counters (immutable view for telemetry).
///
/// Mirrors `ai_cache.py:AiCacheStats`.
class AiCacheStats {
  const AiCacheStats({
    this.hits = 0,
    this.misses = 0,
    this.entries = 0,
    this.estimatedBytes = 0,
  });

  final int hits;
  final int misses;
  final int entries;

  /// Rough character-based footprint of the stored bodies, doubled for UTF-16.
  /// Reported so the storage page can show a size instead of only a count.
  final int estimatedBytes;

  @override
  String toString() => 'AiCacheStats(hits=$hits, misses=$misses, '
      'entries=$entries, estimatedBytes=$estimatedBytes)';
}

/// In-memory LRU cache of AI chat-completion response bodies.
///
/// Ported from `tool/gui/src/backend/ai_cache.py:AiCache`.
///
/// Cache key = `sha256(model | sampling | serialised messages |
/// response_format)`. The API key is deliberately NOT part of the key material
/// (so a key rotation does not invalidate useful draft cache), and the cache
/// never stores the API key or any header - only the model's response body.
///
/// This is intentionally the only cache layer: responses are process-local,
/// bounded by [maxEntries] **and** [maxBytes], and disappear on restart.
@lazySingleton
class AiCache {
  /// Default capacity and on/off state for the production singleton. These
  /// are intentionally not constructor parameters: `injectable_generator`
  /// would otherwise try to resolve them via `gh<int>()` / `gh<bool>()`, and
  /// GetIt does not register primitive types.
  static const int defaultMaxEntries = 200;

  /// Byte ceiling. Entries alone were a poor bound: one generated section body
  /// can be a few hundred KB, so 200 entries could pin tens of megabytes of
  /// strings on a phone. 12 MB keeps a useful working set without pretending
  /// to be free memory.
  static const int defaultMaxBytes = 12 * 1024 * 1024;

  static const bool defaultEnabled = true;

  /// Production constructor used by `@lazySingleton`. Uses the defaults;
  /// tests that need to tweak them should construct via [AiCache.forTest].
  AiCache()
      : _maxEntries = defaultMaxEntries,
        _maxBytes = defaultMaxBytes,
        _enabled = defaultEnabled && defaultMaxEntries > 0;

  /// Test-only constructor that lets specs vary the knobs without exposing
  /// them on the DI-injected production constructor.
  @visibleForTesting
  AiCache.forTest({
    int maxEntries = defaultMaxEntries,
    bool enabled = defaultEnabled,
    int maxBytes = defaultMaxBytes,
  })  : _maxEntries = maxEntries < 0 ? 0 : maxEntries,
        _maxBytes = maxBytes < 0 ? 0 : maxBytes,
        _enabled = enabled && maxEntries > 0;

  final int _maxEntries;
  final int _maxBytes;
  bool _enabled;

  /// Insertion-ordered map; the head is the least-recently-used entry. Dart's
  /// `LinkedHashMap` preserves insertion order, so LRU touch = remove + re-add.
  final LinkedHashMap<String, Map<String, dynamic>> _mem = LinkedHashMap();

  /// Per-entry size estimate, kept alongside `_mem` so eviction stays O(1).
  final Map<String, int> _sizes = <String, int>{};
  int _estimatedBytes = 0;

  bool get enabled => _enabled;
  int get maxEntries => _maxEntries;
  int get maxBytes => _maxBytes;

  /// Toggle the cache at runtime. Disabling does NOT clear entries (mirrors
  /// `ai_cache.py:set_enabled`).
  void setEnabled(bool value) => _enabled = value && _maxEntries > 0;

  /// Stable SHA-256 key for `(model, sampling, messages, response_format)`.
  ///
  /// Messages are serialised with sorted keys (mirroring Python's
  /// `sort_keys=True`) so reordering keys in a message dict does not
  /// invalidate the entry. The API key is intentionally excluded.
  ///
  /// [sampling] must carry every request field that changes the answer but is
  /// not already in the key — temperature, reasoning on/off, max tokens. It
  /// used to be omitted, so changing the temperature (or flipping the reasoning
  /// switch) still replayed the previously cached reply.
  static String makeKey(
    String model,
    List<Map<String, dynamic>> messages,
    Map<String, dynamic>? responseFormat, {
    String sampling = '',
  }) {
    final payload = _canonicalJson({
      'm': model.trim(),
      's': sampling,
      'msg': messages,
      'rf': responseFormat,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  /// Payloads whose message contents total less than this many characters
  /// hash faster synchronously than an isolate hop would cost, so they stay
  /// on the calling isolate. Above it the canonicalisation + SHA-256 is
  /// offloaded (textbook-scale knowledge extractions).
  static const int _offloadThresholdChars = 64 * 1024;

  /// [makeKey] with large payloads computed off the main isolate.
  ///
  /// Produces exactly the same digest as [makeKey] on every path. Small
  /// payloads hash inline (an isolate hop would cost more than the hash
  /// itself); large ones run in a background isolate so canonical-JSON
  /// re-serialisation never janks the UI. Web has no isolates and falls back
  /// to inline hashing; so does an isolate failure (e.g. an unexpectedly
  /// non-sendable message value).
  static Future<String> makeKeyAsync(
    String model,
    List<Map<String, dynamic>> messages,
    Map<String, dynamic>? responseFormat, {
    String sampling = '',
  }) async {
    if (kIsWeb || !_isLargePayload(messages)) {
      return makeKey(model, messages, responseFormat, sampling: sampling);
    }
    try {
      return await Isolate.run(
        () => makeKey(model, messages, responseFormat, sampling: sampling),
      );
    } catch (_) {
      // Non-sendable payload or isolate failure — correctness beats latency.
      return makeKey(model, messages, responseFormat, sampling: sampling);
    }
  }

  /// Cheap upper-bound estimate of the canonicalised payload size: message
  /// contents dominate; other fields contribute a fixed allowance each.
  static bool _isLargePayload(List<Map<String, dynamic>> messages) {
    var chars = 0;
    for (final m in messages) {
      final content = m['content'];
      chars += content is String ? content.length : 64;
      chars += 16;
      if (chars >= _offloadThresholdChars) return true;
    }
    return false;
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

  /// Drop all process-local entries **and** reset the counters.
  ///
  /// The counters are reset too: "clear cache" is the moment the diagnostics
  /// page is opened to verify the clear, and a hit/miss ratio spanning the
  /// previous generation describes traffic that no longer exists in memory.
  void clear() {
    _mem.clear();
    _sizes.clear();
    _estimatedBytes = 0;
    _hits = 0;
    _misses = 0;
  }

  AiCacheStats stats() => AiCacheStats(
        hits: _hits,
        misses: _misses,
        entries: _mem.length,
        estimatedBytes: _estimatedBytes,
      );

  void _putLocked(String key, Map<String, dynamic> value) {
    final size = _estimateBytes(value);
    final previous = _sizes.remove(key);
    if (previous != null) _estimatedBytes -= previous;
    _mem.remove(key);
    _mem[key] = value;
    _sizes[key] = size;
    _estimatedBytes += size;
    _evict();
  }

  void _evict() {
    while (_mem.isNotEmpty &&
        (_mem.length > _maxEntries || _estimatedBytes > _maxBytes)) {
      final oldest = _mem.keys.first;
      _mem.remove(oldest);
      final size = _sizes.remove(oldest);
      if (size != null) _estimatedBytes -= size;
    }
  }

  /// Character-count estimate of a decoded body, doubled for UTF-16 strings.
  ///
  /// Deliberately cheap: a full `jsonEncode` per put would cost more than the
  /// precision is worth, and the number only drives eviction.
  static int _estimateBytes(Object? value) {
    if (value == null) return 0;
    if (value is String) return value.length * 2;
    if (value is num || value is bool) return 8;
    if (value is Map) {
      var total = 0;
      for (final entry in value.entries) {
        total += _estimateBytes(entry.key) + _estimateBytes(entry.value);
      }
      return total + 16;
    }
    if (value is Iterable) {
      var total = 0;
      for (final item in value) {
        total += _estimateBytes(item);
      }
      return total + 8;
    }
    return 32;
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
