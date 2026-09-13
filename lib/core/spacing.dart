// Flutter imports:
import 'package:flutter/material.dart';

/// Shared spacing scale used across the app.
///
/// Prefer these constants over raw `SizedBox(height: 12)` or
/// `EdgeInsets.symmetric(horizontal: 24)` literals so the lesson screens
/// share a single, predictable rhythm.
abstract final class AppSpacing {
  // Numeric scale (one step ≈ 4dp).
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  // Convenience SizedBox gaps. Use these inside `Column`/`Row` children.
  static const SizedBox gapXs = SizedBox(height: xs, width: xs);
  static const SizedBox gapSm = SizedBox(height: sm, width: sm);
  static const SizedBox gapMd = SizedBox(height: md, width: md);
  static const SizedBox gapLg = SizedBox(height: lg, width: lg);

  // Composite EdgeInsets used by page-level content and cards.
  static const EdgeInsets pageGutter =
      EdgeInsets.symmetric(horizontal: 20, vertical: 16);
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
}
