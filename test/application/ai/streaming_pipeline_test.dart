// Unit tests for the streaming pipeline primitives (Plan 3 §21/§26.3):
// delta coalescing (order/loss/cancel) and the auto-scroll throttle/lock.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/ai/chat_auto_scroll_coordinator.dart';
import 'package:turna/application/ai/stream_delta_coalescer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StreamDeltaCoalescer', () {
    test('many deltas within one interval produce one batch', () async {
      final batches = <String>[];
      final c = StreamDeltaCoalescer(
        interval: StreamDeltaCoalescer.testInterval,
        onBatch: batches.add,
      );
      for (var i = 0; i < 100; i++) {
        c.add('x');
      }
      expect(batches, isEmpty, reason: 'nothing before the interval fires');
      await Future<void>.delayed(
          StreamDeltaCoalescer.testInterval * 2);
      expect(batches.length, 1,
          reason: '100 deltas in one interval = one UI commit');
      expect(batches.single, 'x' * 100);
      expect(c.acceptedDeltas, 100);
      c.cancel();
    });

    test('deltas across intervals keep order and lose nothing', () async {
      final batches = <String>[];
      final c = StreamDeltaCoalescer(
        interval: StreamDeltaCoalescer.testInterval,
        onBatch: batches.add,
      );
      c.add('a');
      await Future<void>.delayed(StreamDeltaCoalescer.testInterval * 2);
      c.add('b');
      c.add('c');
      await Future<void>.delayed(StreamDeltaCoalescer.testInterval * 2);
      c.flush();
      expect(batches.join(''), 'abc');
      c.cancel();
    });

    test('flush emits pending content immediately and exactly once',
        () async {
      final batches = <String>[];
      final c = StreamDeltaCoalescer(
        interval: const Duration(seconds: 30),
        onBatch: batches.add,
      );
      c.add('hello');
      c.flush();
      c.flush(); // nothing pending — no second batch
      expect(batches, ['hello']);
      c.cancel();
    });

    test('cancel drops pending content and never emits again', () async {
      final batches = <String>[];
      final c = StreamDeltaCoalescer(
        interval: StreamDeltaCoalescer.testInterval,
        onBatch: batches.add,
      );
      c.add('doomed');
      c.cancel();
      await Future<void>.delayed(StreamDeltaCoalescer.testInterval * 3);
      expect(batches, isEmpty);
    });

    test('unicode boundary fragments are preserved verbatim', () async {
      final batches = <String>[];
      final c = StreamDeltaCoalescer(
        interval: const Duration(seconds: 30),
        onBatch: batches.add,
      );
      // Emoji split across two network fragments.
      c.add('\u{1F1E9}');
      c.add('\u{1F1F7}');
      c.flush();
      expect(batches.single, '🇩🇷');
      c.cancel();
    });
  });

  group('ChatAutoScrollCoordinator', () {
    testWidgets('content updates are throttled to one follow per interval',
        (tester) async {
      final controller = ScrollController();
      final coordinator = ChatAutoScrollCoordinator(
        minInterval: const Duration(milliseconds: 90),
      )..attach(controller);

      final list = ListView.builder(
        controller: controller,
        itemCount: 200,
        itemBuilder: (_, i) => Text('line $i', textDirection: TextDirection.ltr),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox(height: 200, child: list))),
      );
      await tester.pumpAndSettle();

      // 1000 content updates must not schedule 1000 scroll animations.
      for (var i = 0; i < 1000; i++) {
        coordinator.onContentChanged();
      }
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(coordinator.scheduledFollows, lessThanOrEqualTo(3),
          reason: 'throttle coalesces bursts into ~1 follow');

      coordinator.dispose();
      controller.dispose();
    });

    testWidgets('user scrolling up locks following; returning unlocks',
        (tester) async {
      final controller = ScrollController();
      final coordinator = ChatAutoScrollCoordinator()
        ..attach(controller);

      final list = ListView.builder(
        controller: controller,
        itemCount: 200,
        itemBuilder: (_, i) => Text('line $i'),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox(height: 200, child: list))),
      );
      await tester.pumpAndSettle();

      coordinator.lockFollow();
      expect(coordinator.followLocked, isTrue);
      final before = coordinator.scheduledFollows;
      coordinator.onContentChanged();
      expect(coordinator.scheduledFollows, before,
          reason: 'locked coordinator must not follow');

      coordinator.unlockFollow();
      coordinator.onStreamFinished();
      await tester.pumpAndSettle();
      expect(coordinator.scheduledFollows, greaterThan(before));

      coordinator.dispose();
      controller.dispose();
    });
  });
}
