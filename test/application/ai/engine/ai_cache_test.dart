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

  group('AiCache disk mirror', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ai_cache_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('survives a cold restart via the disk mirror', () {
      final key = AiCache.makeKey(
        'm',
        const [
          {'role': 'user', 'content': 'hi'}
        ],
        {'type': 'json_object'},
      );
      final body = {
        'choices': [
          {
            'message': {'content': 'cached!'}
          }
        ]
      };

      // First instance: write to memory + disk.
      final warm = AiCache.forTest(maxEntries: 4);
      warm.enableDiskMirror(tempDir.path);
      warm.put(key, body);
      expect(warm.stats().diskWrites, 1);

      // Second instance: empty memory, same disk dir. A get should lazily
      // promote the disk entry into memory and return it.
      final cold = AiCache.forTest(maxEntries: 4);
      cold.enableDiskMirror(tempDir.path);
      final got = cold.get(key);
      expect(got, isNotNull);
      expect(got!['choices'], isA<List>());
      expect(cold.stats().hits, 1);
    });

    test('clearAll removes both memory and disk entries', () {
      final key = AiCache.makeKey(
        'm',
        const [
          {'role': 'user', 'content': 'hi'}
        ],
        null,
      );
      final cache = AiCache.forTest(maxEntries: 4);
      cache.enableDiskMirror(tempDir.path);
      cache.put(key, {'i': 1});
      cache.clearAll();

      final cold = AiCache.forTest(maxEntries: 4);
      cold.enableDiskMirror(tempDir.path);
      expect(cold.get(key), isNull);
    });
  });
}
