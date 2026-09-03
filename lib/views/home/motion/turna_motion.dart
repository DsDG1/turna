// Flutter imports:
import 'package:flutter/animation.dart';

/// 主页运动语言（Plan「湿地晨光 · 一镜到底」§2）。
///
/// 学习页内时序动画共用这套令牌：同一族时长 + 同一族曲线，让课程卡
/// 展开、底部导航回弹等动效读作同一种「手感」。散落的裸 Duration /
/// Curves 值应迁移到这里，不再各自为政。
///
/// 无障碍约定：调用方用 [scaled] 归零时长。
abstract final class TurnaMotion {
  // ── 时长阶梯 ──
  /// 微反馈：图标换色、按压回弹等一帧级状态切换。
  static const Duration fast = Duration(milliseconds: 140);

  /// 基础：手风琴开合、chevron 旋转、进度环填充。
  static const Duration base = Duration(milliseconds: 200);

  /// 顺滑：区块交叉淡入。
  static const Duration smooth = Duration(milliseconds: 260);

  // ── 曲线族 ──
  /// 默认出场曲线：先快后缓的减速曲线，绝大多数淡入/位移用它。
  static const Curve easeOut = Curves.easeOutCubic;

  /// 弹性入场：小图标的「跳入」，仅用于 24px 级元素，禁止大块面使用。
  static const Curve springIn = Curves.easeOutBack;

  /// 镜头滑动：轻微过冲（~5%）后落位，选中胶囊等镜头级大件位移专用。
  /// 比 [springIn] 温和——过冲幅度减半且无回弹 anticipation，读作
  /// 「滑过头一点再停稳」的物理感，而不是弹跳。
  static const Curve lensGlide = Cubic(0.22, 1.18, 0.36, 1.0);

  /// reduceMotion 时把时长归零，曲线保留（零时长下曲线无意义）。
  static Duration scaled(Duration duration, bool reduceMotion) =>
      reduceMotion ? Duration.zero : duration;

  /// 列表交错入场区间：第 [index] 个元素在 `[step*index, 1]` 内完成，
  /// 起点封顶 [maxStart]，长列表后段不再无限推迟。
  static Interval stagger(
    int index, {
    double step = 0.04,
    double maxStart = 0.20,
    Curve curve = easeOut,
  }) {
    final start = (index * step).clamp(0.0, maxStart);
    return Interval(start, 1.0, curve: curve);
  }
}
