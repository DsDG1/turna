// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/views/theme.dart';

/// L0 环境层：学习页「湿地晨光」背景（Plan §1）。
///
/// 基底沿用 [TurnaTheme.courseTreeGradientFor] 的湿地渐变，其上叠两团
/// 晨雾（径向渐变）。雾团的位移由**滚动视差驱动**：内容上滚时雾团以
/// 0.06x 反向缓慢平移（钳制幅度），静止时完全静止——背景参与滚动叙事
/// 而不是自顾自地循环动画，同时避免常驻 ticker 的电量与测试成本。
///
/// 成本与克制：
/// - 雾团只有渐变着色与 Transform 位移，无逐帧模糊/采样；
/// - 视差经 [ValueNotifier] 只重建雾团 Transform，内容子树零重建；
/// - 整层 [RepaintBoundary] + [IgnorePointer]，不影响命中测试；
/// - reduceMotion / disableAnimations 时雾团完全静止；
/// - 高对比 / 专注模式（quiet）退化为纯基底渐变。
class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({
    required this.child,
    this.reduceMotion = false,
    super.key,
  });

  final Widget child;

  final bool reduceMotion;

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop> {
  /// 滚动视差累计偏移（逻辑像素，钳制在 ±44）。
  final ValueNotifier<double> _mistParallax = ValueNotifier(0);

  @override
  void dispose() {
    _mistParallax.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollUpdateNotification notification) {
    if (widget.reduceMotion) return false;
    final delta = notification.scrollDelta;
    if (delta == null || delta == 0) return false;
    final next = (_mistParallax.value - delta * 0.06).clamp(-44.0, 44.0);
    if (next != _mistParallax.value) {
      _mistParallax.value = next;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final quiet =
        context.select<AccessibilityProvider, bool>(
          (p) => p.highContrast || p.focusMode,
        ) ||
        widget.reduceMotion;

    final Widget background = RepaintBoundary(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: TurnaTheme.courseTreeGradientFor(context),
              ),
            ),
            if (!quiet)
              ValueListenableBuilder<double>(
                valueListenable: _mistParallax,
                builder: (context, parallax, _) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 雾团以固定尺寸锚定在角落，Transform 只做合成器位移。
                    Positioned(
                      top: -110,
                      right: -70,
                      child: Transform.translate(
                        offset: Offset(-parallax * 0.5, parallax),
                        child: const _MistBlob(
                          size: 380,
                          gradient: RadialGradient(
                            colors: [
                              Color(0x1F4FC3DC), // brandSky @ ~0.12
                              Color(0x0A4FC3DC),
                              Color(0x004FC3DC),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -140,
                      left: -90,
                      child: Transform.translate(
                        offset: Offset(parallax * 0.6, -parallax * 0.8),
                        child: const _MistBlob(
                          size: 420,
                          gradient: RadialGradient(
                            colors: [
                              Color(0x17E8A87C), // brandReed @ ~0.09
                              Color(0x08E8A87C),
                              Color(0x00E8A87C),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    return NotificationListener<ScrollUpdateNotification>(
      onNotification: _onScroll,
      child: Stack(
        fit: StackFit.expand,
        children: [
          background,
          // 内容层在背景之上，独立接收命中测试。
          Positioned.fill(child: widget.child),
        ],
      ),
    );
  }
}

class _MistBlob extends StatelessWidget {
  final double size;
  final Gradient gradient;

  const _MistBlob({required this.size, required this.gradient});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
      ),
    );
  }
}
