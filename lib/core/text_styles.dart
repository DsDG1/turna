// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/views/theme.dart';

/// Shared text styles used across the lesson screens.
///
/// Renderers were re-implementing the same caption / prompt TextStyle
/// primitives inline. These helpers make those choices explicit and prevent
/// drift.
///
/// The body/caption styles resolve their color against the current theme via
/// [BuildContext] so text stays readable in both light and dark mode. The
/// check-button label is intentionally fixed (white on the primary button) and
/// remains a `const`.
abstract final class AppTextStyles {
  /// Small uppercase caption shown above each interaction body
  /// ("Fill in the blank", "Listen and pick", etc.).
  static TextStyle caption(BuildContext context) => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: VarnamalaTheme.textHintColor(context),
        letterSpacing: 0.4,
      );

  /// Large body prompt — used for fill-blank, multiple-choice, translate.
  /// Line height intentionally omitted so callers pick their own: fill_blank
  /// passes `.copyWith(height: 1.4)`, while MC / translate rely on the
  /// platform default font height (~1.2) to match the original rendering.
  static TextStyle promptLg(BuildContext context) => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: VarnamalaTheme.textPrimaryColor(context),
      );

  /// Medium body prompt — used for listening, type-the-word, reading MCQs.
  static TextStyle promptMd(BuildContext context) => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: VarnamalaTheme.textPrimaryColor(context),
      );

  /// Bottom action button label ("CHECK" / "CONTINUE" / "GOT IT").
  static const TextStyle buttonLabel = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 0.6,
  );
}