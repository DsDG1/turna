import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:turna/core/theme.dart';

/// 包豪斯几何语汇。
///
/// 前四种是**方框内**的图形（徽章 / 空态 / 分享卡都按 112 的方框设计）；
/// 后两种（[arch] / [diagonalCut]）刻意画到方框**之外**，只用于贴边的
/// 页级主视觉位（[TurnaGeometryBackdrop]）——它们靠"被屏幕边缘切掉"才成立，
/// 放进方框中央会读成一张贴纸。
enum TurnaGeometryKind {
  ripples,
  journey,
  connection,
  achievement,

  /// 半圆拱：直径落在方框下沿并向下越出，弧从左右两侧切开。
  arch,

  /// 斜切留白：45° 楔形从右上角切进来，切口另一侧压一方一圆。
  diagonalCut,

  /// 成就环：两层同心弧 + 环心一点，环心偏右，等右缘切掉一截。
  ///
  /// 和 [achievement] 的区别是**没有那两根短条**——短条是徽章的装饰，
  /// 放到页级/卡级尺度上会变成两块漂浮的色块。要徽章用 [achievement]，
  /// 要环用这个。
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

  final IconData icon;
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
          border: Border.all(
            color: TurnaTheme.glassStroke(context, accent),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(size * 0.19),
          child: Icon(icon, size: iconSize, color: accent),
        ),
      ),
    );
  }
}

/// 页级几何主视觉位：把一个贴边的大尺度几何形垫在页面内容背后。
///
/// 用法上只有一条规矩：**它只能放在有暴露背景或半透明玻璃的位置**。
/// 不透明纸面（[TurnaTheme.flatPaperDecoration]，行族与统计卡）会把几何
/// 整个盖住 —— 那些位置用了等于白画。可用的位置只有三类：
///
/// 1. 页内标题带（个人 / 设置 / 练习的 pageTitle 行）；
/// 2. 列表收尾之后的空白（课程页底部）；
/// 3. 半透明玻璃面背后（个人页 frost 身份卡）—— 只有这一类是给
///    `BackdropFilter` 糊的，也是几何铺开的真正目的。
///
/// 高对比 / [GlassMode.off] 时整层不画：那种模式下背景本来就该干净，
/// 几何只会变成第二层干扰。
class TurnaGeometryBackdrop extends StatelessWidget {
  const TurnaGeometryBackdrop({
    required this.kind,
    required this.child,
    this.alignment = Alignment.topRight,
    this.size = 200,
    this.offset = Offset.zero,
    this.accent,
    this.intensity = 0.86,
    this.flip = false,
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

  @override
  Widget build(BuildContext context) {
    if (!TurnaTheme.glassEnabled(context)) return child;

    Widget field = TurnaGeometry(
      kind: kind,
      size: size,
      accent: accent,
      intensity: intensity,
    );
    if (flip) field = Transform.flip(flipX: true, child: field);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 静态构图单独成层：内容滚动时它不该跟着重绘。
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: Align(
                  alignment: alignment,
                  child: Transform.translate(offset: offset, child: field),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
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
            Offset(w * .70, h * .30), unit * 18, fill..color = sand);
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
            Offset(w * .42, h * .56), unit * 10, fill..color = accent);
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
            Offset(w * .73, h * .25), unit * 13, fill..color = sand);
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
                center: Offset.zero, width: w * .48, height: h * .62),
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
                center: Offset.zero, width: w * .42, height: h * .54),
            Radius.circular(unit * 10),
          ),
          fill..color = sand,
        );
        canvas.restore();
        canvas.drawCircle(
            Offset(w * .51, h * .50), unit * 11, fill..color = accent);
      case TurnaGeometryKind.achievement:
        canvas.drawCircle(
            Offset(w * .50, h * .46), unit * 38, fill..color = soft);
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
      case TurnaGeometryKind.ring:
        // 单环：环心偏右、右缘被切掉一截，剩下的弧读作"从画外进来的圆"。
        //
        // 只画环本身，不带环心圆和内弧 —— 这两个装饰在徽章尺度上有用，
        // 一旦环里放了内容（个人页里是编辑/分享按钮簇），它们必然和内容
        // 打架：环心点正好落在按钮缝隙里，内弧横穿按钮。环要当"内容的
        // 光环"用，就必须是空心的。
        //
        // 尺寸下限：放在毛玻璃卡里时只有**印在玻璃之上**才读得出来。
        // sigma 14 会把 10px 的线整条抹平，再乘 0.72 遮罩就彻底没了
        // （实测过）。要让环进模糊层，线宽得 ≥30px —— 卡片级放不下。
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
    name: 'Geometry · dark', group: 'Wetland mist', brightness: Brightness.dark)
Widget turnaGeometryPreview() => const Padding(
      padding: EdgeInsets.all(24),
      child: TurnaGeometryBadge(icon: Icons.auto_awesome_rounded),
    );

/// 页级形态的样板：拱贴下沿、斜切贴右上，两者都靠边缘裁切成立。
@Preview(name: 'Geometry field · light', group: 'Wetland mist')
@Preview(
    name: 'Geometry field · dark',
    group: 'Wetland mist',
    brightness: Brightness.dark)
Widget turnaGeometryFieldPreview() => const SizedBox(
      width: 320,
      height: 320,
      child: ColoredBox(
        color: Colors.white,
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
