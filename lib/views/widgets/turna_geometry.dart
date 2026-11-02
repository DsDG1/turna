import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:turna/core/theme.dart';

enum TurnaGeometryKind { ripples, journey, connection, achievement }

class TurnaGeometry extends StatelessWidget {
  const TurnaGeometry({
    super.key,
    this.kind = TurnaGeometryKind.ripples,
    this.size = 112,
    this.accent,
    this.child,
  });

  final TurnaGeometryKind kind;
  final double size;
  final Color? accent;
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

class _TurnaGeometryPainter extends CustomPainter {
  const _TurnaGeometryPainter({
    required this.kind,
    required this.accent,
    required this.dark,
    required this.highContrast,
  });

  final TurnaGeometryKind kind;
  final Color accent;
  final bool dark;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final unit = math.min(w, h) / 100;
    final soft = accent.withValues(alpha: highContrast ? 0.10 : 0.16);
    final medium = accent.withValues(alpha: highContrast ? 0.24 : 0.30);
    final sand = highContrast
        ? (dark ? TurnaTheme.darkTextSecondary : TurnaTheme.textSecondary)
            .withValues(alpha: 0.16)
        : TurnaTheme.warmSand.withValues(alpha: dark ? 0.22 : 0.72);
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * (highContrast ? 3 : 5)
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
    }
  }

  @override
  bool shouldRepaint(covariant _TurnaGeometryPainter oldDelegate) =>
      kind != oldDelegate.kind ||
      accent != oldDelegate.accent ||
      dark != oldDelegate.dark ||
      highContrast != oldDelegate.highContrast;
}

@Preview(name: 'Geometry · light', group: 'Wetland mist')
@Preview(
    name: 'Geometry · dark', group: 'Wetland mist', brightness: Brightness.dark)
Widget turnaGeometryPreview() => const Padding(
      padding: EdgeInsets.all(24),
      child: TurnaGeometryBadge(icon: Icons.auto_awesome_rounded),
    );
