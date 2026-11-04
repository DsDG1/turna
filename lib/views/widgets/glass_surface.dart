// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/theme.dart';

/// 白纸上的彩色玻璃 —— 全 app 通用内容容器（ADR 0062）。
///
/// 分层自下而上：
/// ```
/// Container(boxShadow)            // 阴影必须在外层普通 Container 上，
///  └ Material(transparency)       // Ink 的装饰会被 Material 裁掉外阴影
///     └ Ink(decoration: 渐变+描边)
///        └ InkWell                 // 水波纹画在 decoration 之上
///           └ child
/// ```
///
/// [onTap] / [onLongPress] 均为空时不套 Material / InkWell —— 避免要求调用方
/// 必须有 Material 祖先。
///
/// **不要在这个组件上加 `BackdropFilter`**：本项目的玻璃是「白纸上的彩色
/// 玻璃片」，颜色由玻璃自己发，背后没有可模糊的内容。列表项上叠 BackdropFilter
/// 会白烧一次 GPU 采样（全 app 只有胶囊导航和详情浮窗允许用它）。
class GlassSurface extends StatelessWidget {
  /// 玻璃色相。取值见 [TurnaTheme.glassFocus] / [TurnaTheme.glassContainer] /
  /// [TurnaTheme.glassNeutral] 等语义常量。
  final Color accent;

  final Widget child;

  /// 材质层级，默认 [GlassLevel.l1]（内容卡）。表单页用 [GlassLevel.l1Subtle]。
  final GlassLevel level;

  /// 圆角。默认 `cardRadius`（4）。徽章级用 `radiusRound` 或自身尺寸一半。
  final BorderRadius? radius;

  /// 淡彩浓度倍率，1.0 为规范值。供 [SoftCard.tintAlpha] 这类既有强度参数映射。
  final double scale;

  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  final VoidCallback? onTap;
  final GestureLongPressCallback? onLongPress;

  /// 无障碍提示（如长按语义）。仅在有手势时生效。
  final String? semanticsHint;

  const GlassSurface({
    super.key,
    required this.accent,
    required this.child,
    this.level = GlassLevel.l1,
    this.radius,
    this.scale = 1.0,
    this.padding,
    this.margin,
    this.onTap,
    this.onLongPress,
    this.semanticsHint,
  });

  @override
  Widget build(BuildContext context) {
    final r = radius ?? BorderRadius.circular(TurnaTheme.cardRadius);
    final interactive = onTap != null || onLongPress != null;

    // 阴影与 fill 分开取：fill 传空阴影，阴影挂外层 Container。
    final decoration = TurnaTheme.glassDecoration(
      context,
      accent,
      level: level,
      borderRadius: r,
      boxShadow: const <BoxShadow>[],
      scale: scale,
    );
    final shadow = TurnaTheme.glassEnabled(context)
        ? TurnaTheme.glassShadow(context, accent, level: level)
        : const <BoxShadow>[];

    Widget content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    if (interactive) {
      content = Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: decoration,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            onLongPress: onLongPress,
            child: content,
          ),
        ),
      );
    } else {
      content = DecoratedBox(decoration: decoration, child: content);
    }

    final card = DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: shadow),
      child: content,
    );

    Widget result = card;
    if (semanticsHint != null && interactive) {
      result = Semantics(
        button: true,
        onTap: onTap,
        onLongPress: onLongPress,
        hint: semanticsHint,
        child: card,
      );
    }
    return margin == null ? result : Padding(padding: margin!, child: result);
  }
}
