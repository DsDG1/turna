import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/views/home/scroll_hide_policy.dart';

void main() {
  late ScrollHidePolicy policy;

  setUp(() {
    policy = ScrollHidePolicy();
  });

  // Scrolls [deltas] into the policy; returns the flipped flags in order.
  List<bool> scroll(Iterable<double> deltas, {double pixels = 40}) {
    return deltas
        .map(
          (d) => policy.onScrollUpdate(
            axis: Axis.vertical,
            pixels: pixels,
            scrollDelta: d,
          ),
        )
        .toList();
  }

  test('hides only after a continuous downward gesture reaches the threshold',
      () {
    final flips = scroll([32, 32]);
    expect(flips, [false, true]);
    expect(policy.hidden, isTrue);
  });

  test('a short downward gesture alone does not hide', () {
    scroll([40]);
    expect(policy.hidden, isFalse);
  });

  test('a fling-style delta hides in one update', () {
    scroll([180]);
    expect(policy.hidden, isTrue);
  });

  test('small incremental scrolls accumulate within one gesture', () {
    final flips = scroll([20, 20, 20, 10]);
    expect(flips.last, isTrue);
    expect(policy.hidden, isTrue);
  });

  test('settling (idle) resets gesture progress', () {
    scroll([40]);
    policy.onSettled();
    scroll([40]);
    expect(policy.hidden, isFalse,
        reason: 'two separate sub-threshold gestures must not combine');
  });

  test('upward motion resets the downward run (hysteresis)', () {
    scroll([50, -5, 50]);
    expect(policy.hidden, isFalse,
        reason: 'the -5px correction restarts the downward run');
  });

  test('hidden bar reveals after cumulative upward travel', () {
    scroll([100]);
    expect(policy.hidden, isTrue);

    final flips = scroll([-10, -14]);
    expect(flips.last, isTrue);
    expect(policy.hidden, isFalse);
  });

  test('overscroll or top (pixels <= 0) always reveals', () {
    scroll([100]);
    expect(policy.hidden, isTrue);

    policy.onScrollUpdate(
      axis: Axis.vertical,
      pixels: 0,
      scrollDelta: -4,
    );
    expect(policy.hidden, isFalse);

    scroll([100]);
    policy.onScrollUpdate(
      axis: Axis.vertical,
      pixels: -12,
      scrollDelta: 4,
    );
    expect(policy.hidden, isFalse);
  });

  test('horizontal scroll is ignored', () {
    policy.onScrollUpdate(
      axis: Axis.horizontal,
      pixels: 500,
      scrollDelta: 400,
    );
    expect(policy.hidden, isFalse);

    scroll([100]);
    expect(policy.hidden, isTrue);

    policy.onScrollUpdate(
      axis: Axis.horizontal,
      pixels: 500,
      scrollDelta: -400,
    );
    expect(policy.hidden, isTrue);
  });

  test('reveal() shows immediately and clears gesture runs', () {
    scroll([100]);
    expect(policy.hidden, isTrue);

    policy.reveal();
    expect(policy.hidden, isFalse);

    scroll([40]);
    expect(policy.hidden, isFalse,
        reason: 'runs were cleared, so the 40px swipe starts from zero');
  });

  test('null scrollDelta keeps current visibility', () {
    scroll([100]);
    final flipped = policy.onScrollUpdate(
      axis: Axis.vertical,
      pixels: 40,
      scrollDelta: null,
    );
    expect(flipped, isFalse);
    expect(policy.hidden, isTrue);
  });
}
