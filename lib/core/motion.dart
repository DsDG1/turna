import 'package:flutter/animation.dart';

abstract final class TurnaMotion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration smooth = Duration(milliseconds: 260);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve springIn = Curves.easeOutBack;
  static const Curve lensGlide = Cubic(0.22, 1.18, 0.36, 1.0);

  static Duration scaled(Duration duration, bool reduceMotion) =>
      reduceMotion ? Duration.zero : duration;

  static Interval stagger(
    int index, {
    double step = 0.04,
    double maxStart = 0.20,
    double span = 1.0,
    Curve curve = easeOut,
  }) {
    final start = (index * step).clamp(0.0, maxStart);
    return Interval(start, (start + span).clamp(start, 1.0), curve: curve);
  }
}
