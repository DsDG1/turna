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

  // ──「湿地雾光」版面文字角色（P1 排版表，P2 组件起消费）──────────────────
  //
  // 与上面做题域的 caption / prompt 角色互补：这里管**页面级**版面——标题、
  // 区块、正文、辅助信息与重点数字。行高按 P1 的 1.45–1.65 正文区间取值；
  // 标题类 1.2–1.3（多行长标题换行不散）。

  /// 页面标题：一级页面与章节开篇（28–36，取 30）。
  static TextStyle pageTitle(BuildContext context) => TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: TurnaTheme.textPrimaryColor(context),
        height: 1.25,
      );

  /// 区块标题：页面内分组（18–20，取 19）。
  static TextStyle sectionTitle(BuildContext context) => TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: TurnaTheme.textPrimaryColor(context),
        height: 1.3,
      );

  /// 卡片标题：入口、设置组与结果标题（16–18，取 16）。
  static TextStyle cardTitle(BuildContext context) => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: TurnaTheme.textPrimaryColor(context),
        height: 1.35,
      );

  /// 正文：说明、释义与可持续阅读内容。
  static TextStyle bodyText(BuildContext context) => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: TurnaTheme.textPrimaryColor(context),
        height: 1.5,
      );

  /// 辅助信息：时间、来源与次要统计（13）。
  static TextStyle captionSm(BuildContext context) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: TurnaTheme.textSecondaryColor(context),
        height: 1.4,
      );

  /// 重点数字：今日待复习、完成概览等少量位置（28–36，取 34）。
  ///
  /// 色彩由调用方按语义给（待复习数用 teal 深档，警示值用语义色）；
  /// 默认跟随主文字。
  static TextStyle metricHero(
    BuildContext context, {
    Color? color,
  }) =>
      TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: color ?? TurnaTheme.textPrimaryColor(context),
        height: 1.1,
      );
}
