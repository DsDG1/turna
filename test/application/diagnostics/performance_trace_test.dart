import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/diagnostics/performance_trace.dart';

void main() {
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
}
