import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/diagnostics/cache_diagnostics_registry.dart';
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
}
