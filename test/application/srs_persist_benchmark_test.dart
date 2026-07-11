// Performance baseline for SRS state JSON encoding (ADR 0011).
// Does not assert hard wall-clock budgets (CI machines vary); logs timings
// and verifies encode/decode integrity at scale.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/application/srs_queue_provider.dart';
import 'package:varnamala/domain/course/srs_word.dart';

Map<String, SrsWord> _buildState(int n) {
  final now = DateTime(2026, 7, 11);
  final map = <String, SrsWord>{};
  for (var i = 0; i < n; i++) {
    map['w-$i'] = SrsWord(
      wordId: 'w-$i',
      dueAt: now.add(Duration(days: i % 30)),
      intervalDays: 1 + (i % 10),
      ease: 2.5,
      reps: i % 5,
      lapses: i % 3,
      type: i.isEven ? SrsItemType.word : SrsItemType.expression,
    );
  }
  return map;
}

void main() {
  test('encodeStateForPersist scales to 500 / 2000 / 10000 entries', () {
    final sizes = [500, 2000, 10000];
    final timings = <int, int>{};

    for (final n in sizes) {
      final state = _buildState(n);
      final sw = Stopwatch()..start();
      final encoded = SrsQueueProvider.encodeStateForPersist(state);
      sw.stop();
      timings[n] = sw.elapsedMicroseconds;

      expect(encoded, isNotEmpty);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded.length, n);

      // ignore: avoid_print
      print(
        'SRS encodeStateForPersist n=$n → '
        '${sw.elapsedMicroseconds}µs '
        '(${(sw.elapsedMicroseconds / 1000).toStringAsFixed(2)}ms) '
        'bytes=${encoded.length}',
      );
    }

    // Soft documentation for ADR 0011: shard threshold is 5ms @ >2000.
    // We do not fail the suite if a slow CI host exceeds it — the ADR records
    // the measured values from a representative run.
    final at2k = timings[2000]!;
    final at10k = timings[10000]!;
    expect(at2k, greaterThan(0));
    expect(at10k, greaterThan(0));
  });
}
