// Consolidated unit tests for diagnostics telemetry:
// PerformanceTrace, StorageWriteTelemetry, and CacheDiagnosticsRegistry.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/diagnostics/cache_diagnostics_registry.dart';
import 'package:turna/application/diagnostics/performance_trace.dart';
import 'package:turna/application/diagnostics/storage_write_telemetry.dart';

class _FakeCache implements CacheDiagnosticsAdapter {
  _FakeCache(this.owner, this.entries, this.bytes);

  @override
  final String owner;
  int entries;
  final int? bytes;

  @override
  Future<CacheFootprint> inspect() async => CacheFootprint(
        owner: owner,
        entries: entries,
        estimatedBytes: bytes,
      );

  @override
  Future<CacheClearResult> clearRegenerable() async {
    final before = entries;
    entries = 0;
    return CacheClearResult(owner: owner, clearedEntries: before);
  }
}

void main() {
  group('PerformanceTrace', () {
    test('trace ring is bounded and summary reports P50/P95', () {
      final trace = PerformanceTrace(capacity: 3);
      for (final ms in [10, 20, 30, 40]) {
        trace.record(
          feature: 'dashboard',
          operation: 'load',
          duration: Duration(milliseconds: ms),
          resultSize: 7,
          cacheStatus: TraceCacheStatus.miss,
        );
      }

      expect(trace.events, hasLength(3));
      expect(trace.summary(), contains('P50 30ms'));
      expect(trace.summary(), contains('P95 40ms'));
    });

    test('serialized trace cannot retain paths, keys, prompts or card text', () {
      final trace = PerformanceTrace();
      trace.record(
        feature: '/home/alice/private/card answer',
        operation: 'Bearer super-secret-key prompt',
        duration: const Duration(milliseconds: 80),
        resultSize: 1,
        outcome: TraceOutcome.error,
      );
      final serialized = trace.toSafeJson();

      expect(serialized, contains('invalid'));
      expect(serialized, isNot(contains('/home/alice')));
      expect(serialized, isNot(contains('super-secret-key')));
      expect(serialized, isNot(contains('card answer')));
      expect(serialized, isNot(contains('prompt')));
    });
  });

  group('Storage and Cache Diagnostics', () {
    test('write telemetry is bounded and serializes no values', () {
      final telemetry = StorageWriteTelemetry(capacity: 2);
      telemetry.record(key: 'mistake.log', estimatedBytes: 10);
      telemetry.record(key: 'study.logs.recent', estimatedBytes: 20);
      telemetry.record(key: 'cosmetics.equipped.avatarRing', estimatedBytes: 5);

      expect(telemetry.samples, hasLength(2));
      final serialized = jsonEncode(telemetry.toSafeJson());
      expect(serialized, isNot(contains('secret-card-answer')));
      expect(serialized, isNot(contains('value')));
      expect(serialized, contains('estimatedBytes'));
    });

    test('cache registry entries and clear results match each adapter', () async {
      final first = _FakeCache('ai.responseCache', 7, null);
      final second = _FakeCache('flutter.imageCache', 3, 4096);
      final registry = CacheDiagnosticsRegistry([first, second]);

      final before = await registry.inspectAll();
      expect(before.map((row) => row.entries), [7, 3]);
      expect(before.first.estimatedBytes, isNull);
      expect(before.last.estimatedBytes, 4096);

      final cleared = await registry.clearRegenerable();
      expect(cleared.map((row) => row.clearedEntries), [7, 3]);
      expect((await registry.inspectAll()).map((row) => row.entries), [0, 0]);
    });
  });
}
