import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:turna/core/motion.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/views/widgets/turna_icon.dart';

/// 包豪斯几何语汇。
///
/// 前五种是**方框内**的图形（徽章 / 空态 / 断签 / 分享卡均按 112 方框设计）；
/// 后三种（[arch] / [diagonalCut] / [ring]）刻意画到方框**之外**，只用于贴边的
/// 页级主视觉位（[TurnaGeometryBackdrop]）。
enum TurnaGeometryKind {
  ripples,
  journey,
  connection,
  achievement,

  /// 熄灭的连胜火焰：包豪斯菱形切分 + 静默弧线，替代旧栅格 `offFire.png`。
  brokenStreak,

  /// 半圆拱：直径落在方框下沿并向下越出，弧从左右两侧切开。
  arch,

  /// 斜切留白：45° 楔形从右上角切进来，切口另一侧压一方一圆。
  diagonalCut,

  /// 单环：环心偏右，右缘由页面或卡片边缘切掉一截。
  ring,
}

class TurnaGeometry extends StatelessWidget {
  const TurnaGeometry({
    super.key,
    this.kind = TurnaGeometryKind.ripples,
    this.size = 112,
    this.accent,
    this.intensity = 1.0,
    this.child,
  });

  final TurnaGeometryKind kind;
  final double size;
  final Color? accent;

  /// 整体浓度的乘数。页级主视觉位要比徽章淡，靠它压，别改画笔里的常数。
  final double intensity;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? TurnaTheme.brandTeal;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _TurnaGeometryPainter(
            kind: kind,
            accent: color,
            dark: Theme.of(context).brightness == Brightness.dark,
            highContrast: !TurnaTheme.glassEnabled(context),
            intensity: intensity,
          ),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}

class TurnaGeometryBadge extends StatelessWidget {
  const TurnaGeometryBadge({
    super.key,
    required this.icon,
    this.kind = TurnaGeometryKind.achievement,
    this.accent = TurnaTheme.anatolianClay,
    this.size = 112,
    this.iconSize = 40,
  });

  final TurnaIconId icon;
  final TurnaGeometryKind kind;
  final Color accent;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return TurnaGeometry(
      kind: kind,
      accent: accent,
      size: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: TurnaTheme.glassFill(context, accent),
          border: Border.all(color: TurnaTheme.glassStroke(context, accent)),
        ),
        child: Padding(
          padding: EdgeInsets.all(size * 0.19),
          child: TurnaIcon(icon, size: iconSize, color: accent),
        ),
      ),
    );
  }
}

/// 页级几何主视觉位：把一个贴边的大尺度几何形垫在页面内容背后。
///
/// 装饰层以小幅视差跟随子滚动视口，并可在内容展开时局部模糊、淡化。
/// 它不参与命中测试或语义；减少动效时静止，高对比 / [GlassMode.off] 时不画。
class TurnaGeometryBackdrop extends StatefulWidget {
  const TurnaGeometryBackdrop({
    required this.kind,
    required this.child,
    this.alignment = Alignment.topRight,
    this.size = 200,
    this.offset = Offset.zero,
    this.accent,
    this.intensity = 0.86,
    this.flip = false,
    this.muted = false,
    super.key,
  });

  final TurnaGeometryKind kind;
  final Widget child;

  /// 方框贴在页面的哪个角。[arch] 请配 [Alignment.bottomCenter] 或
  /// [Alignment.bottomLeft]/[Alignment.bottomRight]。
  final Alignment alignment;

  /// 方框边长。几何本身会越出这个方框，所以它只是"锚点尺寸"。
  final double size;

  /// 在 [alignment] 基础上的位移。给负值把形推出边缘，让切口更自然。
  final Offset offset;

  final Color? accent;

  /// 浓度乘数。页级默认 0.86 —— 主视觉是构图的一部分，不该比内容先被
  /// 看见。
  final double intensity;

  /// 水平镜像。同一个形可以同时服务左右两侧（[diagonalCut] 常用）。
  final bool flip;

  /// 内容展开时弱化装饰，避免几何线条与正文争夺注意力。
  final bool muted;

  @override
  State<TurnaGeometryBackdrop> createState() => _TurnaGeometryBackdropState();
}

class _TurnaGeometryBackdropState extends State<TurnaGeometryBackdrop> {
  static const _parallaxFactor = 0.12;
  static const _maxParallax = 72.0;
  static const _mutedBlurSigma = 6.0;
  static const _minimumMutedOpacity = 0.30;

  double _parallaxOffset = 0;

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        MediaQuery.disableAnimationsOf(context)) {
      return false;
    }
    final next = (-notification.metrics.pixels * _parallaxFactor)
        .clamp(-_maxParallax, _maxParallax)
        .toDouble();
    if (next == _parallaxOffset) return false;
    setState(() => _parallaxOffset = next);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!TurnaTheme.glassEnabled(context)) return widget.child;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = TurnaMotion.scaled(TurnaMotion.fast, reduceMotion);

    Widget field = TurnaGeometry(
      kind: widget.kind,
      size: widget.size,
      accent: widget.accent,
      intensity: widget.intensity,
    );
    if (widget.flip) field = Transform.flip(flipX: true, child: field);

    final mutedField = TweenAnimationBuilder<double>(
      tween: Tween(end: widget.muted ? 1 : 0),
      duration: duration,
      curve: TurnaMotion.easeOut,
      builder: (context, progress, child) {
        Widget result = Opacity(
          key: const Key('turna-geometry-opacity'),
          opacity: 1 - progress * (1 - _minimumMutedOpacity),
          child: child,
        );
        if (progress > 0.001) {
          result = ImageFiltered(
            key: const Key('turna-geometry-muted-blur'),
            imageFilter: ImageFilter.blur(
              sigmaX: _mutedBlurSigma * progress,
              sigmaY: _mutedBlurSigma * progress,
            ),
            child: result,
          );
        }
        return result;
      },
      child: RepaintBoundary(child: field),
    );

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Align(
                  alignment: widget.alignment,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: reduceMotion ? 0 : _parallaxOffset),
                    duration: duration,
                    curve: TurnaMotion.easeOut,
                    builder: (context, parallax, child) => Transform.translate(
                      key: const Key('turna-geometry-parallax'),
                      offset: widget.offset + Offset(0, parallax),
                      child: child,
                    ),
                    child: mutedField,
                  ),
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _TurnaGeometryPainter extends CustomPainter {
  const _TurnaGeometryPainter({
    required this.kind,
    required this.accent,
    required this.dark,
    required this.highContrast,
    this.intensity = 1.0,
  });

  final TurnaGeometryKind kind;
  final Color accent;
  final bool dark;
  final bool highContrast;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final unit = math.min(w, h) / 100;
    final a = intensity.clamp(0.0, 1.0);
    final soft = accent.withValues(alpha: (highContrast ? 0.10 : 0.16) * a);
    final medium = accent.withValues(alpha: (highContrast ? 0.24 : 0.30) * a);
    final solid = accent.withValues(alpha: (highContrast ? 0.42 : 0.62) * a);
    final sand = highContrast
        ? (dark ? TurnaTheme.darkTextSecondary : TurnaTheme.textSecondary)
              .withValues(alpha: 0.16 * a)
        : TurnaTheme.warmSand.withValues(alpha: (dark ? 0.22 : 0.72) * a);
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * (highContrast ? 3 : 5)
      ..strokeCap = StrokeCap.round;

    // 页级形态是"大面"，线要按面积收细：按 min 边 2.6% 走，比徽章细一档。
    final hair = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * (highContrast ? 1.8 : 2.4)
      ..strokeCap = StrokeCap.round;

    switch (kind) {
      case TurnaGeometryKind.ripples:
        canvas.drawCircle(
          Offset(w * .70, h * .30),
          unit * 18,
          fill..color = sand,
        );
        stroke.color = medium;
        for (var i = 0; i < 3; i++) {
          canvas.drawArc(
            Rect.fromCenter(
              center: Offset(w * .42, h * .56),
              width: unit * (48 + i * 22),
              height: unit * (48 + i * 22),
            ),
            math.pi * .12,
            math.pi * 1.55,
            false,
            stroke,
          );
        }
        canvas.drawCircle(
          Offset(w * .42, h * .56),
          unit * 10,
          fill..color = accent,
        );
      case TurnaGeometryKind.journey:
        final arch = RRect.fromRectAndCorners(
          Rect.fromLTWH(w * .24, h * .14, w * .52, h * .72),
          topLeft: Radius.circular(unit * 26),
          topRight: Radius.circular(unit * 26),
        );
        canvas.drawRRect(arch, fill..color = soft);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * .36, h * .36, w * .28, h * .50),
            Radius.circular(unit * 14),
          ),
          fill..color = medium,
        );
        canvas.drawCircle(
          Offset(w * .73, h * .25),
          unit * 13,
          fill..color = sand,
        );
        canvas.drawRect(
          Rect.fromLTWH(w * .10, h * .78, w * .22, h * .08),
          fill..color = accent,
        );
      case TurnaGeometryKind.connection:
        canvas.save();
        canvas.translate(w * .40, h * .48);
        canvas.rotate(-.24);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: w * .48,
              height: h * .62,
            ),
            Radius.circular(unit * 10),
          ),
          fill..color = soft,
        );
        canvas.restore();
        canvas.save();
        canvas.translate(w * .62, h * .52);
        canvas.rotate(.24);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: w * .42,
              height: h * .54,
            ),
            Radius.circular(unit * 10),
          ),
          fill..color = sand,
        );
        canvas.restore();
        canvas.drawCircle(
          Offset(w * .51, h * .50),
          unit * 11,
          fill..color = accent,
        );
      case TurnaGeometryKind.achievement:
        canvas.drawCircle(
          Offset(w * .50, h * .46),
          unit * 38,
          fill..color = soft,
        );
        canvas.drawArc(
          Rect.fromCircle(center: Offset(w * .50, h * .46), radius: unit * 43),
          math.pi * .14,
          math.pi * 1.45,
          false,
          stroke..color = medium,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * .16, h * .72, w * .24, h * .12),
            Radius.circular(unit * 3),
          ),
          fill..color = sand,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * .62, h * .74, w * .22, h * .10),
            Radius.circular(unit * 3),
          ),
          fill..color = accent,
        );
      case TurnaGeometryKind.diagonalCut:
        // 一刀切掉右上角：三角面填满角部，斜边是唯一的那条线。
        //
        // 前两版都败在"薄"——留了两条几乎与屏幕角平行的斜线，读作渲染
        // 残留。真正的斜切要有**面积**：切口大面积、边缘一条、角内一枚
        // 方。三个元素就够，多一个就脏。
        final corner = Path()
          ..moveTo(w * .20, -h * .02)
          ..lineTo(w * 1.02, -h * .02)
          ..lineTo(w * 1.02, h * .78)
          ..close();
        canvas.drawPath(corner, fill..color = soft);
        // 斜边细线：贴切口外侧平行走，两端各收一点，不触到画面边缘。
        canvas.drawLine(
          Offset(w * .27, 0),
          Offset(w, h * .70),
          hair..color = medium,
        );
        // 角内实心方：唯一的重色，落在切口深处，不贴斜边（贴边会读成
        // 一块被切下来的标签）。
        canvas.drawRect(
          Rect.fromLTWH(w * .78, h * .28, w * .11, h * .085),
          fill..color = solid,
        );
      case TurnaGeometryKind.arch:
        // 半圆拱：直径**必须落在方框内**。
        //
        // 第一版半径取了长边的 0.62 倍，直径被屏幕左右切掉 —— 读到的是
        // 一座土丘，不是半圆。半圆成立的前提是那条平的直径看得见，所以
        // 半径收到 0.44，两端各留 6% 的边，直径压在 0.98h 上。
        final radius = w * .44;
        final baseline = h * .98;
        final center = Offset(w * .50, baseline);
        final dome = Rect.fromCircle(center: center, radius: radius);
        canvas.drawArc(dome, math.pi, math.pi, true, fill..color = soft);
        // 拱线：比拱面外扩一圈，两端各收一点，读作"第二道拱"。
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius * 1.14),
          math.pi * 1.08,
          math.pi * .84,
          false,
          hair..color = medium,
        );
        // 直径线：压住拱脚，两端越出方框，让半圆有立足的地方。
        canvas.drawRect(
          Rect.fromLTWH(-w * .30, baseline - unit * .8, w * 1.6, unit * 1.6),
          fill..color = medium,
        );
      case TurnaGeometryKind.brokenStreak:
        // 静默几何熄火：外弧 + 切分菱形 + 底部微烬方锚，替代旧栅格 offFire.png。
        canvas.drawCircle(
          Offset(w * .50, h * .52),
          unit * 36,
          highContrast ? (stroke..color = medium) : (fill..color = soft),
        );
        final diamond = Path()
          ..moveTo(w * .50, h * .14)
          ..lineTo(w * .72, h * .52)
          ..lineTo(w * .50, h * .82)
          ..lineTo(w * .28, h * .52)
          ..close();
        canvas.drawPath(
          diamond,
          highContrast ? (stroke..color = accent) : (fill..color = medium),
        );
        // 斜切线表达中断
        canvas.drawLine(
          Offset(w * .24, h * .28),
          Offset(w * .76, h * .76),
          stroke..color = accent,
        );
        // 底部余温方点
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(w * .50, h * .88),
            width: unit * 14,
            height: unit * 5,
          ),
          fill..color = sand,
        );
      case TurnaGeometryKind.ring:
        final c = Offset(w * .72, h * .50);
        final r = math.min(w, h) * .38;
        canvas.drawCircle(c, r, stroke..color = soft);
    }
  }

  @override
  bool shouldRepaint(covariant _TurnaGeometryPainter oldDelegate) =>
      kind != oldDelegate.kind ||
      accent != oldDelegate.accent ||
      dark != oldDelegate.dark ||
      highContrast != oldDelegate.highContrast ||
      intensity != oldDelegate.intensity;
}

@Preview(name: 'Geometry · light', group: 'Wetland mist')
@Preview(
  name: 'Geometry · dark',
  group: 'Wetland mist',
  brightness: Brightness.dark,
)
Widget turnaGeometryPreview() => const Padding(
  padding: EdgeInsets.all(24),
  child: TurnaGeometryBadge(icon: TurnaIconId.spark),
);

/// 页级形态的样板：拱贴下沿、斜切贴右上，两者都靠边缘裁切成立。
@Preview(name: 'Geometry field · light', group: 'Wetland mist')
@Preview(
  name: 'Geometry field · dark',
  group: 'Wetland mist',
  brightness: Brightness.dark,
)
Widget turnaGeometryFieldPreview() => const SizedBox(
  width: 320,
  height: 320,
  child: ColoredBox(
    color: TurnaTheme.scaffoldBackground,
    child: Stack(
      children: [
        Positioned.fill(
          child: TurnaGeometryBackdrop(
            kind: TurnaGeometryKind.diagonalCut,
            child: SizedBox.shrink(),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: TurnaGeometry(
            kind: TurnaGeometryKind.arch,
            size: 320,
            intensity: 0.86,
          ),
        ),
      ],
    ),
  ),
);
