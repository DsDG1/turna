/// 全局包豪斯几何加载器（ADR 0075 / 计划 §5.1）。
///
/// 替代散落各处的 `CircularProgressIndicator`。由圆弧与湿地青几何块构成：
/// - [TurnaLoader.page]：整页居中加载态（可选说明文案）；
/// - [TurnaLoader.inline]：卡片 / 列表局部加载态；
/// - [TurnaLoader.button]：按钮内紧凑加载态（默认使用 [TurnaTheme.textOnPrimary]）。
///
/// 尊重系统禁用动画与 [AccessibilityProvider.reducedMotion]：开启减少动效时
/// 静止绘制几何标记，不空转帧泵。
library;

// Dart imports:
import 'dart:math' as math;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';

class TurnaLoader extends StatefulWidget {
  const TurnaLoader({
    this.size = 28,
    this.strokeWidth = 2.4,
    this.color,
    this.label,
    super.key,
  }) : _defaultOnPrimary = false;

  /// 整页居中加载态。
  const TurnaLoader.page({this.label, this.color, super.key})
      : size = 36,
        strokeWidth = 2.6,
        _defaultOnPrimary = false;

  /// 局部内联加载态。
  const TurnaLoader.inline({this.size = 20, this.color, super.key})
      : strokeWidth = 2.0,
        label = null,
        _defaultOnPrimary = false;

  /// 按钮内紧凑加载态。
  const TurnaLoader.button({this.color, super.key})
      : size = 18,
        strokeWidth = 2.0,
        label = null,
        _defaultOnPrimary = true;

  final double size;
  final double strokeWidth;
  final Color? color;
  final String? label;
  final bool _defaultOnPrimary;

  @override
  State<TurnaLoader> createState() => _TurnaLoaderState();
}

class _TurnaLoaderState extends State<TurnaLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool _reduceMotion(BuildContext context) {
    final a11y = context.read<AccessibilityProvider?>();
    return MediaQuery.disableAnimationsOf(context) ||
        (a11y?.reducedMotion ?? false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _controller.stop();
      _controller.value = 0.25;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.color ??
        (widget._defaultOnPrimary
            ? TurnaTheme.textOnPrimary
            : TurnaTheme.brandTeal);
    final track = TurnaTheme.dividerBg(context);
    final reduced = _reduceMotion(context);

    final glyph = Semantics(
      label: widget.label ?? 'Loading',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: reduced
            ? CustomPaint(
                painter: _BauhausLoaderPainter(
                  progress: 0.25,
                  accent: accent,
                  track: track,
                  strokeWidth: widget.strokeWidth,
                ),
              )
            : AnimatedBuilder(
                animation: _controller,
                builder: (_, __) => CustomPaint(
                  painter: _BauhausLoaderPainter(
                    progress: _controller.value,
                    accent: accent,
                    track: track,
                    strokeWidth: widget.strokeWidth,
                  ),
                ),
              ),
      ),
    );

    if (widget.label == null || widget.label!.isEmpty) return glyph;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        glyph,
        const SizedBox(height: AppSpacing.md),
        Text(
          widget.label!,
          style: AppTextStyles.captionSm(context),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _BauhausLoaderPainter extends CustomPainter {
  const _BauhausLoaderPainter({
    required this.progress,
    required this.accent,
    required this.track,
    required this.strokeWidth,
  });

  final double progress;
  final Color accent;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = track.withValues(alpha: 0.6);
    canvas.drawCircle(center, radius, trackPaint);

    final startAngle = progress * math.pi * 2 - math.pi / 2;
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..color = accent;
    canvas.drawArc(rect, startAngle, math.pi * 0.75, false, arcPaint);

    // 中心包豪斯小方锚点
    final dotSize = math.max(3.0, size.shortestSide * 0.16);
    final dotRect = Rect.fromCenter(
      center: center,
      width: dotSize,
      height: dotSize,
    );
    canvas.drawRect(dotRect, Paint()..color = accent.withValues(alpha: 0.72));
  }

  @override
  bool shouldRepaint(_BauhausLoaderPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.accent != accent ||
      oldDelegate.track != track ||
      oldDelegate.strokeWidth != strokeWidth;
}

@Preview(name: 'Turna loader · light', group: 'Wetland mist')
@Preview(
  name: 'Turna loader · dark',
  group: 'Wetland mist',
  brightness: Brightness.dark,
)
Widget turnaLoaderPreview() => Padding(
  padding: const EdgeInsets.all(AppSpacing.xl),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      TurnaLoader.page(label: '加载中'),
      const SizedBox(width: AppSpacing.xl),
      TurnaLoader.inline(),
    ],
  ),
);
