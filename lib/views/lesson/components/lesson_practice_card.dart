// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/theme.dart';

/// 视觉风格变体. 不同 variant 仅改底色和边框色阶, 共享同一套渐变 + 阴影,
/// 以保证练习域所有主卡观感一致.
enum LessonPracticeCardVariant {
  /// 浅色白底 + 细 teal 描边 — Anki 正面 / ShowWord 单词卡
  front,

  /// 轻 teal 底色 + 强 teal 描边 — Anki 翻面
  back,

  /// 中性白底 + 最弱描边 — Translate 源句卡片等需要主卡语义的场景
  surface,
}

/// 练习页面的「半拟物质感」主卡容器.
///
/// 视觉构成 (自下而上):
/// 1. 双层柔阴影 ([TurnaTheme.surfaceL2Shadow]) — 浅色投品牌深蓝, 深色投
///    极弱白光. 深色画布是纯黑, navy 阴影在上面等于不存在, 这是深色模式
///    "卡片发平"的根因.
/// 2. 底色 + 顶光渐变 ([TurnaTheme.cardTopLight]) — 模拟磨砂面的受光面.
/// 3. 细描边 (1px) — 不抢戏, 仅保持轮廓清晰.
///
/// 该组件被 [AnkiCardRenderer] / [ShowWordRenderer] / [TranslateSentenceRenderer]
/// 共用. 替换某个 renderer 的卡片容器时, 只需把外层 `Container` /
/// `Material(elevation:...)` 替换为本组件即可.
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = _resolveColors(context, isDark, variant);
    final radius = BorderRadius.circular(TurnaTheme.radiusLarge);

    // 只给 gradient. 同时传 `color` 时 BoxDecoration 只画 gradient,
    // 底色会静默失效 —— back 变体的品牌底就是这么被吞掉的.
    final fill = BoxDecoration(
      gradient: TurnaTheme.cardTopLight(context, colors.fill),
      borderRadius: radius,
      border: Border.all(color: colors.border, width: 1),
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
        boxShadow: TurnaTheme.surfaceL2Shadow(context),
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

  _CardColors _resolveColors(
    BuildContext context,
    bool isDark,
    LessonPracticeCardVariant v,
  ) {
    final base = TurnaTheme.surfaceL2Fill(context);
    switch (v) {
      case LessonPracticeCardVariant.front:
        return _CardColors(
          fill: base,
          border: TurnaTheme.brandTeal.withValues(alpha: isDark ? 0.30 : 0.20),
        );
      case LessonPracticeCardVariant.back:
        return _CardColors(
          fill: Color.alphaBlend(
            TurnaTheme.brandTeal.withValues(alpha: isDark ? 0.22 : 0.10),
            base,
          ),
          border: TurnaTheme.brandTeal.withValues(alpha: isDark ? 0.55 : 0.45),
        );
      case LessonPracticeCardVariant.surface:
        return _CardColors(
          fill: base,
          border: TurnaTheme.brandTeal.withValues(alpha: isDark ? 0.22 : 0.15),
        );
    }
  }
}

class _CardColors {
  final Color fill;
  final Color border;
  const _CardColors({required this.fill, required this.border});
}
