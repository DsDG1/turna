import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/views/home/scroll_hide_policy.dart';

void main() {
  bool next({
    bool hidden = false,
    Axis axis = Axis.vertical,
    required ScrollDirection direction,
    double pixels = 40,
  }) {
    return ScrollHidePolicy.nextHidden(
      hidden: hidden,
      axis: axis,
      direction: direction,
      pixels: pixels,
    );
  }

  test('scroll down past threshold hides the bar', () {
    expect(
      next(direction: ScrollDirection.reverse, pixels: 20),
      isTrue,
    );
  });

  test('scroll down near the top does not hide', () {
    expect(
      next(direction: ScrollDirection.reverse, pixels: 4),
      isFalse,
    );
  });

  test('scroll up reveals a hidden bar', () {
    expect(
      next(hidden: true, direction: ScrollDirection.forward),
      isFalse,
    );
  });

  test('overscroll or top (pixels <= 0) always reveals', () {
    expect(
      next(
        hidden: true,
        direction: ScrollDirection.reverse,
        pixels: 0,
      ),
      isFalse,
    );
    expect(
      next(
        hidden: true,
        direction: ScrollDirection.idle,
        pixels: -12,
      ),
      isFalse,
    );
  });

  test('idle keeps the current visibility', () {
    expect(
      next(hidden: true, direction: ScrollDirection.idle),
      isTrue,
    );
    expect(
      next(hidden: false, direction: ScrollDirection.idle),
      isFalse,
    );
  });

  test('horizontal scroll is ignored', () {
    expect(
      next(
        axis: Axis.horizontal,
        direction: ScrollDirection.reverse,
        pixels: 80,
      ),
      isFalse,
    );
    expect(
      next(
        hidden: true,
        axis: Axis.horizontal,
        direction: ScrollDirection.forward,
        pixels: 80,
      ),
      isTrue,
    );
  });
}
