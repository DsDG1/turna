// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/theme.dart';

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
  ///
  /// 11/600 + 0.8 字距: 它是"分区标记"而不是正文, 压到 11 才能和题干
  /// (22/600) 拉开三档层级; 14 时和选项文字抢视线.
  static TextStyle caption(BuildContext context) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: TurnaTheme.textHintColor(context),
        letterSpacing: 0.8,
        height: 1.4,
      );

  /// Large body prompt — used for fill-blank, multiple-choice, translate.
  ///
  /// 行高在这里统一给 1.35; 调用方仍可用 `copyWith(height: ...)` 覆盖
  /// (fill_blank 用 1.4). 不给行高时中英混排的行距会随字形漂移.
  static TextStyle promptLg(BuildContext context) => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: TurnaTheme.textPrimaryColor(context),
        height: 1.35,
      );

  /// Medium body prompt — used for listening, type-the-word, reading MCQs.
  static TextStyle promptMd(BuildContext context) => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: TurnaTheme.textPrimaryColor(context),
        height: 1.4,
      );

  /// Bottom action button label ("CHECK" / "CONTINUE" / "GOT IT").
  static const TextStyle buttonLabel = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 0.6,
  );
}
