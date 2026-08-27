// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_cache.dart';

void main() {
  group('AiCache.makeKey', () {
    test('stable for identical inputs', () {
      final k1 = AiCache.makeKey(
        'deepseek-v4-pro',
        const [
          {'role': 'system', 'content': 's'},
          {'role': 'user', 'content': 'hi'},
        ],
        {'type': 'json_object'},
      );
      final k2 = AiCache.makeKey(
        'deepseek-v4-pro',
        const [
          {'role': 'system', 'content': 's'},
          {'role': 'user', 'content': 'hi'},
        ],
        {'type': 'json_object'},
      );
      expect(k1, k2);
    });

    test('differs when any field changes', () {
      final base = AiCache.makeKey(
        'm',
        const [
          {'role': 'user', 'content': 'hi'}
        ],
        null,
      );
      expect(
        AiCache.makeKey(
          'm2',
          const [
            {'role': 'user', 'content': 'hi'}
          ],
          null,
        ),
        isNot(base),
      );
      expect(
        AiCache.makeKey(
          'm',
          const [
            {'role': 'user', 'content': 'hi2'}
          ],
          null,
        ),
        isNot(base),
      );
      expect(
        AiCache.makeKey(
          'm',
          const [
            {'role': 'user', 'content': 'hi'}
          ],
          {'type': 'json_object'},
        ),
        isNot(base),
      );
    });

    test('canonical: message key order does not change the hash', () {
      // Mirrors Python's `sort_keys=True`: reordering keys inside a message
      // dict must not invalidate the entry.
      final k1 = AiCache.makeKey(
        'm',
        const [
          {'content': 'hi', 'role': 'user'},
        ],
        null,
      );
      final k2 = AiCache.makeKey(
        'm',
        const [
          {'role': 'user', 'content': 'hi'},
        ],
        null,
      );
      expect(k1, k2);
    });
  });

  group('AiCache.makeKeyAsync', () {
    test('matches makeKey for small payloads (inline path)', () async {
      final messages = [
        {'role': 'system', 'content': 's'},
        {'role': 'user', 'content': 'hi'},
      ];
      expect(
        await AiCache.makeKeyAsync('m', messages, {'type': 'json_object'}),
        AiCache.makeKey('m', messages, {'type': 'json_object'}),
      );
    });

    test('matches makeKey for large payloads (isolate path)', () async {
      // Content beyond the 64 KiB offload threshold forces the background
      // isolate path on the VM; the digest must stay identical.
      final big = 'x' * (64 * 1024 + 256);
      final messages = [
        {'role': 'system', 'content': big},
        {'role': 'user', 'content': 'extract'},
      ];
      expect(
        await AiCache.makeKeyAsync('m', messages, null),
        AiCache.makeKey('m', messages, null),
      );
    });
  });

  group('AiCache LRU', () {
    test('hit returns the stored body and bumps hits', () {
      final cache = AiCache.forTest(maxEntries: 4);
      const key = 'k';
      cache.put(key, {
        'choices': [
          {
            'message': {'content': 'hi'}
          }
        ]
      });
      final got = cache.get(key);
      expect(got, isNotNull);
      expect(got!['choices'], isA<List>());
      expect(cache.stats().hits, 1);
      expect(cache.stats().misses, 0);
    });

    test('miss returns null and bumps misses', () {
      final cache = AiCache.forTest(maxEntries: 4);
      expect(cache.get('absent'), isNull);
      expect(cache.stats().misses, 1);
      expect(cache.stats().hits, 0);
    });

    test('evicts the least-recently-used entry past maxEntries', () {
      final cache = AiCache.forTest(maxEntries: 3);
      cache.put('a', {'i': 1});
      cache.put('b', {'i': 2});
      cache.put('c', {'i': 3});
      // Touch 'a' so 'b' becomes the LRU.
      cache.get('a');
      cache.put('d', {'i': 4}); // over capacity -> evict LRU ('b')
      expect(cache.get('a'), isNotNull);
      expect(cache.get('b'), isNull); // evicted
      expect(cache.get('c'), isNotNull);
      expect(cache.get('d'), isNotNull);
      expect(cache.stats().entries, 3);
    });

    test('clear() drops memory entries', () {
      final cache = AiCache.forTest(maxEntries: 4);
      cache.put('a', {'i': 1});
      cache.clear();
      expect(cache.get('a'), isNull);
      expect(cache.stats().entries, 0);
    });

    test('disabled cache always misses and never stores', () {
      final cache = AiCache.forTest(maxEntries: 4, enabled: false);
      cache.put('a', {'i': 1});
      expect(cache.get('a'), isNull);
      expect(cache.stats().entries, 0);
    });
  });

  group('AiCache memory-only contract', () {
    test('entries never survive a new cache instance', () {
      final warm = AiCache.forTest(maxEntries: 4)..put('key', {'i': 1});
      expect(warm.get('key'), {'i': 1});

      final cold = AiCache.forTest(maxEntries: 4);
      expect(cold.get('key'), isNull);
      expect(cold.stats().entries, 0);
    });

    test('removed disk symbols and source files cannot return', () {
      const forbidden = <String>[
        'enableDiskMirror',
        'attachDiskCache',
        'diskWrites',
        'diskErrors',
        'DiskCacheStore',
      ];
      final sources = <File>[
        File('lib/application/ai/engine/ai_cache.dart'),
        File('lib/application/ai/engine/ai_engine.dart'),
      ];
      for (final source in sources) {
        final text = source.readAsStringSync();
        for (final symbol in forbidden) {
          expect(text, isNot(contains(symbol)),
              reason: '${source.path} reintroduced $symbol');
        }
      }
      expect(
        File('lib/application/ai/engine/ai_cache_disk_io.dart').existsSync(),
        isFalse,
      );
      expect(
        File('lib/application/ai/engine/ai_cache_disk_web.dart').existsSync(),
        isFalse,
      );
    });
  });
}
