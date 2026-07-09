// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:words625/views/theme.dart';

/// Shared text styles used across the lesson screens.
///
/// Renderers were re-implementing the same caption / prompt TextStyle
/// primitives inline. These constants make those choices explicit and
/// prevent drift.
abstract final class AppTextStyles {
  /// Small uppercase caption shown above each interaction body
  /// ("Fill in the blank", "Listen and pick", etc.).
  static const TextStyle caption = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: VarnamalaTheme.textHint,
    letterSpacing: 0.4,
  );

  /// Large body prompt — used for fill-blank, multiple-choice, translate.
  /// Line height intentionally omitted so callers pick their own: fill_blank
  /// passes `.copyWith(height: 1.4)`, while MC / translate rely on the
  /// platform default font height (~1.2) to match the original rendering.
  static const TextStyle promptLg = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    color: VarnamalaTheme.textPrimary,
  );

  /// Medium body prompt — used for listening, type-the-word, reading MCQs.
  static const TextStyle promptMd = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: VarnamalaTheme.textPrimary,
  );

  /// Bottom action button label ("CHECK" / "CONTINUE" / "GOT IT").
  static const TextStyle buttonLabel = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 0.6,
  );
}
