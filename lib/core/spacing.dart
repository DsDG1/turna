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

  // 「湿地雾光」版面节奏（docs/design-refresh/p1-language-and-wireframes.md
  // 栅格行）：纵向节奏 8 / 12 / 16 / 24 / 32 / 48，主边距 24、紧凑内容边距 16。
  static const double xxxl = 48;

  // Convenience SizedBox gaps. Use these inside `Column`/`Row` children.
  static const SizedBox gapXs = SizedBox(height: xs, width: xs);
  static const SizedBox gapSm = SizedBox(height: sm, width: sm);
  static const SizedBox gapMd = SizedBox(height: md, width: md);
  static const SizedBox gapLg = SizedBox(height: lg, width: lg);

  // Composite EdgeInsets used by page-level content and cards.
  static const EdgeInsets pageGutter =
      EdgeInsets.symmetric(horizontal: 20, vertical: 16);
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);

  // ──「湿地雾光」栅格 token（P1 定型，P2 组件起消费）────────────────────
  //

  /// 页面主边距（24）。紧凑内容列（题面、目录行内缩）用 [pageMarginCompact]。
  static const double pageMargin = xl;

  /// 紧凑内容边距（16）：会话进度头、书写区、行内元素的水平内缩。
  static const double pageMarginCompact = lg;

  /// 主边距对应的水平 EdgeInsets。
  static const EdgeInsets pageGutterMist =
      EdgeInsets.symmetric(horizontal: pageMargin);

  /// 学习主列（课程树、题面、会话画布）的最大内容宽度。
  static const double studyColumnMaxWidth = 720;

  /// 统计 / 表单 / 报告页的最大内容宽度。
  static const double formColumnMaxWidth = 840;
}
