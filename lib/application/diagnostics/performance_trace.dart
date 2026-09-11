import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

enum TraceCacheStatus { hit, miss, stale, notApplicable }

enum TraceOutcome { ok, error, cancelled }

@immutable
class PerformanceTraceEvent {
  const PerformanceTraceEvent({
    required this.feature,
    required this.operation,
    required this.durationMs,
    required this.resultSize,
    required this.cacheStatus,
    required this.outcome,
    required this.recordedAt,
  });

  final String feature;
  final String operation;
  final int durationMs;
  final int resultSize;
  final TraceCacheStatus cacheStatus;
  final TraceOutcome outcome;
  final DateTime recordedAt;

  Map<String, Object> toJson() => {
        'feature': feature,
        'operation': operation,
        'durationMs': durationMs,
        'resultSize': resultSize,
        'cacheStatus': cacheStatus.name,
        'outcome': outcome.name,
        'recordedAt': recordedAt.toIso8601String(),
      };
}

class PerformanceTrace {
  PerformanceTrace({this.capacity = 200});

  static final PerformanceTrace instance = PerformanceTrace();

  final int capacity;
  final Queue<PerformanceTraceEvent> _events = Queue();
  final Map<String, List<int>> _durations = {};

  List<PerformanceTraceEvent> get events => List.unmodifiable(_events);

  static const Map<String, int> slowThresholdMs = {
    'dashboard.load': 50,
    'insights.load': 50,
    'ai.ask': 1000,
    'ai.firstChunk': 500,
    'storage.scan': 50,
    'anki.import': 50,
    'dao.query': 50,
  };

  void record({
    required String feature,
    required String operation,
    required Duration duration,
    required int resultSize,
    TraceCacheStatus cacheStatus = TraceCacheStatus.notApplicable,
    TraceOutcome outcome = TraceOutcome.ok,
  }) {
    final durationMs = duration.inMilliseconds;
    final safeFeature = _safeIdentifier(feature);
    final safeOperation = _safeIdentifier(operation);
    final key = '$safeFeature.$safeOperation';
    final aggregate = _durations.putIfAbsent(key, () => <int>[]);
    aggregate.add(durationMs);
    if (aggregate.length > 200) aggregate.removeAt(0);

    final threshold = slowThresholdMs[key] ?? 50;
    if (kReleaseMode && outcome == TraceOutcome.ok && durationMs < threshold) {
      return;
    }
    if (capacity <= 0) return;
    _events.addLast(PerformanceTraceEvent(
      feature: safeFeature,
      operation: safeOperation,
      durationMs: durationMs,
      resultSize: resultSize < 0 ? 0 : resultSize,
      cacheStatus: cacheStatus,
      outcome: outcome,
      recordedAt: DateTime.now(),
    ));
    while (_events.length > capacity) {
      _events.removeFirst();
    }
  }

  String _safeIdentifier(String value) =>
      RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(value) ? value : 'invalid';

  String summary({int slowLimit = 5}) {
    final lines = <String>['性能摘要（脱敏）'];
    final keys = _durations.keys.toList()..sort();
    for (final key in keys) {
      final values = List<int>.of(_durations[key]!)..sort();
      lines.add('$key：P50 ${_percentile(values, 0.50)}ms · '
          'P95 ${_percentile(values, 0.95)}ms · ${values.length} 次');
    }
    final slow = _events.toList()
      ..sort((a, b) => b.durationMs.compareTo(a.durationMs));
    if (slow.isNotEmpty) {
      lines.add('慢操作 Top-$slowLimit：');
      for (final event in slow.take(slowLimit)) {
        lines.add('- ${event.feature}.${event.operation} '
            '${event.durationMs}ms / ${event.resultSize} / '
            '${event.outcome.name}');
      }
    }
    return lines.join('\n');
  }

  String toSafeJson() =>
      jsonEncode([for (final event in _events) event.toJson()]);

  int _percentile(List<int> sorted, double percentile) {
    if (sorted.isEmpty) return 0;
    final index = ((sorted.length - 1) * percentile).ceil();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  @visibleForTesting
  void clear() {
    _events.clear();
    _durations.clear();
  }
}
