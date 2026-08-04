// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/views/theme.dart';

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
/// 1. 双层柔阴影 ([TurnaTheme.elevatedCardShadow]) — 模拟光照下的悬浮感.
/// 2. 底色 + 极轻白色渐变 (左上→右下, 0.55→0.0 透明) — 模拟磨砂面的光照面.
/// 3. 细描边 (1.5px) — 不抢戏, 仅保持轮廓清晰.
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

  const LessonPracticeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.variant = LessonPracticeCardVariant.front,
    this.minHeight = 200,
    this.appearAnimation = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = _resolveColors(context, isDark, variant);

    final card = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: padding,
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        // 渐变模拟「光照下磨砂面」, 不透明度极低.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.04 : 0.55),
            Colors.white.withValues(alpha: 0.0),
          ],
        ),
        border: Border.all(color: colors.border, width: 1.5),
        boxShadow: TurnaTheme.elevatedCardShadow,
      ),
      child: child,
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
    switch (v) {
      case LessonPracticeCardVariant.front:
        return _CardColors(
          fill: TurnaTheme.cardBg(context),
          border: TurnaTheme.brandTeal.withValues(alpha: 0.20),
        );
      case LessonPracticeCardVariant.back:
        return _CardColors(
          fill: TurnaTheme.brandTeal.withValues(alpha: isDark ? 0.18 : 0.10),
          border: TurnaTheme.brandTeal.withValues(alpha: 0.45),
        );
      case LessonPracticeCardVariant.surface:
        return _CardColors(
          fill: TurnaTheme.cardBg(context),
          border: TurnaTheme.brandTeal.withValues(alpha: 0.15),
        );
    }
  }
}

class _CardColors {
  final Color fill;
  final Color border;
  const _CardColors({required this.fill, required this.border});
}
