import 'dart:collection';

import 'package:flutter/foundation.dart';

@immutable
class StorageWriteSample {
  const StorageWriteSample({
    required this.key,
    required this.estimatedBytes,
    required this.elapsedMicros,
    required this.recordedAt,
  });

  final String key;
  final int estimatedBytes;
  final int elapsedMicros;
  final DateTime recordedAt;

  Map<String, Object> toSafeJson() => {
        'key': key,
        'estimatedBytes': estimatedBytes,
        'elapsedMicros': elapsedMicros,
        'recordedAt': recordedAt.toIso8601String(),
      };
}

@immutable
class StorageWriteAggregate {
  const StorageWriteAggregate({
    required this.key,
    required this.count,
    required this.estimatedBytes,
    required this.elapsedMicros,
  });

  final String key;
  final int count;
  final int estimatedBytes;
  final int elapsedMicros;
}

/// Value-free write amplification telemetry.
///
/// Only a stable key name, encoded byte count and duration are retained in a
/// bounded ring. Values, prompts, paths and card content are never accepted by
/// this API, which makes accidental payload logging structurally impossible.
class StorageWriteTelemetry {
  StorageWriteTelemetry({this.capacity = 200});

  static final StorageWriteTelemetry instance = StorageWriteTelemetry();

  final int capacity;
  final Queue<StorageWriteSample> _samples = Queue<StorageWriteSample>();

  List<StorageWriteSample> get samples => List.unmodifiable(_samples);

  void record({
    required String key,
    required int estimatedBytes,
    Duration elapsed = Duration.zero,
  }) {
    if (capacity <= 0) return;
    _samples.addLast(StorageWriteSample(
      key: key,
      estimatedBytes: estimatedBytes < 0 ? 0 : estimatedBytes,
      elapsedMicros: elapsed.inMicroseconds,
      recordedAt: DateTime.now(),
    ));
    while (_samples.length > capacity) {
      _samples.removeFirst();
    }
  }

  List<StorageWriteAggregate> top({int limit = 8}) {
    final aggregates = <String, StorageWriteAggregate>{};
    for (final sample in _samples) {
      final old = aggregates[sample.key];
      aggregates[sample.key] = StorageWriteAggregate(
        key: sample.key,
        count: (old?.count ?? 0) + 1,
        estimatedBytes: (old?.estimatedBytes ?? 0) + sample.estimatedBytes,
        elapsedMicros: (old?.elapsedMicros ?? 0) + sample.elapsedMicros,
      );
    }
    final rows = aggregates.values.toList()
      ..sort((a, b) {
        final byBytes = b.estimatedBytes.compareTo(a.estimatedBytes);
        return byBytes != 0 ? byBytes : b.count.compareTo(a.count);
      });
    return rows.take(limit).toList(growable: false);
  }

  List<Map<String, Object>> toSafeJson() =>
      [for (final sample in _samples) sample.toSafeJson()];

  @visibleForTesting
  void clear() => _samples.clear();
}
