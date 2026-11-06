// Flutter imports:
import 'dart:ui' show ImageFilter;

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
/// **默认档不要加 `BackdropFilter`**：本项目的玻璃是「白纸上的彩色玻璃片」，
/// 颜色由玻璃自己发，标准档的填充是不透明的，背后可糊的内容会被盖掉，
/// 只剩一次白烧的 GPU 采样。真模糊走 [frost]（ADR 0068）—— 那一档的填充
/// 是半透明的，糊才有意义，且每页至多两张。
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

  /// 真毛玻璃（ADR 0068）：半透明填充 + 实时背景模糊 + 顶部镜面受光边。
  ///
  /// 只在「一屏里唯一的主体卡」上开：练习主行动卡、复习主卡、个人头卡、
  /// 完成卡。**不要用在列表行上** —— 每处 `BackdropFilter` 都是一次全屏
  /// 采样，一屏叠三张直接掉帧。高对比 / [GlassMode.off] 时自动退回普通档。
  final bool frost;

  /// 卡面不透明度，仅 [frost] 生效。0.72 是「模糊读得出来、正文还稳」的
  /// 平衡点；低于 0.6 长文本会随背景明暗起伏。
  final double frostOpacity;

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
    this.frost = false,
    this.frostOpacity = 0.72,
  });

  @override
  Widget build(BuildContext context) {
    final r = radius ?? BorderRadius.circular(TurnaTheme.cardRadius);
    final interactive = onTap != null || onLongPress != null;
    final glassOn = TurnaTheme.glassEnabled(context);
    // 高对比下模糊会自动关掉：视线要的是轮廓与对比，不是材质。
    final useFrost = frost && glassOn;
    final effectiveLevel = useFrost ? GlassLevel.l2Frost : level;

    // 阴影与 fill 分开取：fill 传空阴影，阴影挂外层 Container。
    final decoration = useFrost
        ? BoxDecoration(
            gradient: TurnaTheme.glassFrostFill(
              context,
              accent,
              opacity: frostOpacity,
            ),
            borderRadius: r,
            border: Border.all(
              color: TurnaTheme.glassStroke(
                context,
                accent,
                level: effectiveLevel,
              ),
              width: 1,
            ),
          )
        : TurnaTheme.glassDecoration(
            context,
            accent,
            level: level,
            borderRadius: r,
            boxShadow: const <BoxShadow>[],
            scale: scale,
          );
    final shadow = glassOn
        ? TurnaTheme.glassShadow(context, accent, level: effectiveLevel)
        : const <BoxShadow>[];

    Widget content =
        padding == null ? child : Padding(padding: padding!, child: child);

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

    if (useFrost) {
      // 模糊必须在填充之下：先糊背景，再压半透明彩面。
      // RepaintBoundary 把采样范围隔离在这一张卡内。
      content = RepaintBoundary(
        child: ClipRRect(
          borderRadius: r,
          clipBehavior: Clip.antiAlias,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: TurnaTheme.frostSigma,
              sigmaY: TurnaTheme.frostSigma,
            ),
            child: content,
          ),
        ),
      );
      // 顶部镜面受光边：玻璃上缘最薄、受光最强，1px 就够读出「一片玻璃」。
      content = Stack(
        children: [
          content,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: FractionallySizedBox(
                widthFactor: 0.88,
                alignment: Alignment.topCenter,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.62),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: useFrost ? const <BoxShadow>[] : shadow,
      ),
      child: content,
    );

    // 模糊层已经自带 RepaintBoundary + 裁切，阴影改挂最外层普通 Box。
    final shell = useFrost
        ? DecoratedBox(
            decoration: BoxDecoration(borderRadius: r, boxShadow: shadow),
            child: card,
          )
        : card;

    Widget result = shell;
    if (semanticsHint != null && interactive) {
      result = Semantics(
        button: true,
        onTap: onTap,
        onLongPress: onLongPress,
        hint: semanticsHint,
        child: shell,
      );
    }
    return margin == null ? result : Padding(padding: margin!, child: result);
  }
}
