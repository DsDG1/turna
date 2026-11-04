// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/theme.dart';

/// 视觉风格变体. 不同 variant 仅改底色和边框色阶, 共享同一套渐变 + 阴影,
/// 以保证练习域所有主卡观感一致.
enum LessonPracticeCardVariant {
  /// 浅色白底 + 细 teal 描边 — Anki 正面
  front,

  /// 轻 teal 底色 + 强 teal 描边 — Anki 翻面
  back,
}

/// 练习页面的主卡容器（ADR 0062：白纸上的彩色玻璃）.
///
/// 视觉构成 (自下而上):
/// 1. 同色相双层投影 ([TurnaTheme.glassShadow]) — 玻璃的可读性来自影子
///    投在白纸上的色相，不是灰色投影。深色画布是纯黑，另叠一层向上白光
///    模拟顶光，否则卡片会「发平」.
/// 2. 淡彩渐变 + 白高光预混层 ([TurnaTheme.glassFill]) — 上浅下深的厚度感.
/// 3. 1px 同色相描边 ([TurnaTheme.glassStroke]) — 有色玻璃边缘因折射更沉.
///
/// 该组件被 [AnkiCardRenderer] 与官方卡宿主（记忆卡域 fixture）共用——
/// 翻面语义的玻璃卡。题面类容器（生词卡 / 源句 / 大题面）在「湿地雾光」
/// §7.1 后走纸面 `SessionRecallCanvas`, 不再用玻璃卡。
class LessonPracticeCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final LessonPracticeCardVariant variant;
  final double minHeight;

  /// 是否启用入场缩放动画. 默认 `true`. 在动画堆叠的场景 (如 Anki 翻转中
  /// 嵌入卡片) 应关闭, 避免曲线打架.
  final bool appearAnimation;

  /// 整张卡作为点击目标时的回调 (ShowWord 的"点卡片继续").
  ///
  /// 传了它才会切到 `Material + Ink` 的绘制路径 —— 见 [build] 里的注释.
  final VoidCallback? onTap;

  const LessonPracticeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.variant = LessonPracticeCardVariant.front,
    this.minHeight = 200,
    this.appearAnimation = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _resolveColors(variant);
    final radius = BorderRadius.circular(TurnaTheme.cardRadius);

    // 单层 gradient（白高光预混进 stop）。同时传 `color` 时 BoxDecoration
    // 只画 gradient，底色会静默失效 —— 这里压根不给 color。
    final fill = TurnaTheme.glassDecoration(
      context,
      colors.accent,
      level: colors.level,
      borderRadius: radius,
      boxShadow: const <BoxShadow>[],
      scale: colors.scale,
    );

    final Widget body;
    if (onTap == null) {
      body = Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: padding,
        decoration: fill,
        child: child,
      );
    } else {
      // 用 Ink 而不是 Container: Container 是不透明绘制层, 会把上层 Material
      // 的水波纹整个盖掉, 点下去毫无反馈. Ink 把底色画在 Material 上, 水波纹
      // 浮在底色之上, 而卡片内部的手势 (点词读音) 仍先于卡片本身命中.
      body = Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: fill,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      );
    }

    final card = Container(
      // 阴影挂在最外层普通 Container 上: Ink 的装饰会被 Material 裁掉外阴影.
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: TurnaTheme.glassShadow(
          context,
          colors.accent,
          level: colors.level,
        ),
      ),
      child: body,
    );

    if (!appearAnimation) return card;

    // 240ms 缩放 + 淡入, 让主卡"软进入". autoAdvance 类型的 ShowWord 感受
    // 最直接; 翻转型 (Anki) 关闭此动画避免与翻转曲线叠加.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        final opacity = ((scale - 0.96) / 0.04).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: card,
    );
  }

  _CardColors _resolveColors(LessonPracticeCardVariant v) {
    // ADR 0062：主卡统一走 L2 浮起层（teal），back 变体靠提高淡彩浓度区分
    // 「已翻面」，不再另造一套底色 + 描边组合。
    switch (v) {
      case LessonPracticeCardVariant.front:
        return const _CardColors(
          accent: TurnaTheme.glassFocus,
          level: GlassLevel.l2,
        );
      case LessonPracticeCardVariant.back:
        return const _CardColors(
          accent: TurnaTheme.glassFocus,
          level: GlassLevel.l2,
          scale: 1.35,
        );
    }
  }
}

class _CardColors {
  final Color accent;
  final GlassLevel level;

  /// 淡彩浓度倍率，1.0 为规范值。
  final double scale;

  const _CardColors({
    required this.accent,
    required this.level,
    this.scale = 1.0,
  });
}
