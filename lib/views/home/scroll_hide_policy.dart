// Flutter imports:
import 'package:flutter/rendering.dart';

/// Android-style hide-on-scroll for the home tab capsule, driven by
/// accumulated scroll distance instead of direction flips.
///
/// Sign convention (Flutter: offset increasing = later items coming into
/// view = the user browsing *down* the list): positive [scrollDelta]
/// accumulates toward hiding, negative delta toward revealing. A single
/// gesture must cover [hideAfterPixels] before the bar hides, so resting at
/// the list bottom never strands a visible bar behind a later stray swipe.
///
/// Runs reset when the scroll settles ([onSettled]) or visibility flips, so
/// half-gestures never combine across moments of rest. Does not morph width;
/// callers only translate the bar.
class ScrollHidePolicy {
  /// Continuous downward browsing needed before the bar hides.
  static const double hideAfterPixels = 64;

  /// Upward travel needed before a hidden bar comes back.
  static const double revealAfterPixels = 24;

  double _hideRun = 0;
  double _revealRun = 0;
  bool _hidden = false;

  bool get hidden => _hidden;

  /// Feeds one scroll-update frame. Returns true when visibility flipped.
  bool onScrollUpdate({
    required Axis axis,
    required double pixels,
    required double? scrollDelta,
  }) {
    if (axis != Axis.vertical) return false;
    if (pixels <= 0) return _apply(false);
    final delta = scrollDelta ?? 0;
    if (delta > 0) {
      _hideRun += delta;
      _revealRun = 0;
      if (!_hidden && _hideRun >= hideAfterPixels) return _apply(true);
    } else if (delta < 0) {
      _revealRun -= delta;
      _hideRun = 0;
      if (_hidden && _revealRun >= revealAfterPixels) return _apply(false);
    }
    return false;
  }

  /// Clears gesture runs once the user scroll direction goes idle.
  void onSettled() {
    _hideRun = 0;
    _revealRun = 0;
  }

  /// Shows the bar immediately (tab tap / tab switch) and resets runs.
  void reveal() {
    _apply(false);
  }

  bool _apply(bool value) {
    onSettled();
    if (value == _hidden) return false;
    _hidden = value;
    return true;
  }
}
