// Flutter imports:
import 'package:flutter/rendering.dart';

/// Android-style hide-on-scroll for the home tab capsule.
///
/// [ScrollDirection.reverse] = content moving up = user scrolling down.
/// Does not morph width; callers only translate the bar.
class ScrollHidePolicy {
  static const double revealAtTopPixels = 8;

  /// Returns whether the bar should be hidden after this user-scroll event.
  static bool nextHidden({
    required bool hidden,
    required Axis axis,
    required ScrollDirection direction,
    required double pixels,
  }) {
    if (axis != Axis.vertical) return hidden;
    if (pixels <= 0) return false;
    if (direction == ScrollDirection.idle) return hidden;
    if (direction == ScrollDirection.reverse && pixels > revealAtTopPixels) {
      return true;
    }
    if (direction == ScrollDirection.forward) return false;
    return hidden;
  }
}
