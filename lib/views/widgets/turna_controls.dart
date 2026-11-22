/// 全局 4px 几何表单控件（ADR 0075）。
///
/// 由原设置域局部控件提升至跨域公共层，全 App 开关与滑块统一走 4px 近直角
/// 几何语言，与按钮、输入框、卡片形成一致秩序。
library;

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/motion.dart';
import 'package:turna/core/theme.dart';

/// 全局 4px 几何开关（56×48 触控热区、48×28 轨道、4px 圆角）。
class TurnaSwitch extends StatelessWidget {
  const TurnaSwitch({required this.value, required this.onChanged, super.key});

  final bool value;
  final ValueChanged<bool>? onChanged;

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity == null || velocity == 0) return;
    final next = velocity > 0;
    if (next != value) onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      key: const Key('turna-switch'),
      button: true,
      enabled: enabled,
      toggled: value,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        onHorizontalDragEnd: enabled ? _onHorizontalDragEnd : null,
        child: SizedBox(
          width: 56,
          height: 48,
          child: Center(
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: value ? 1 : 0),
                duration: TurnaMotion.scaled(TurnaMotion.fast, reduceMotion),
                curve: TurnaMotion.easeOut,
                builder: (context, progress, _) {
                  return Container(
                    key: const Key('turna-switch-track'),
                    width: 48,
                    height: 28,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: value
                          ? TurnaTheme.brandTeal
                          : TurnaTheme.dividerBg(context),
                      borderRadius: TurnaTheme.borderRadius,
                      border: Border.all(
                        color: value
                            ? TurnaTheme.brandTeal
                            : TurnaTheme.textHintColor(context),
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.lerp(
                        Alignment.centerLeft,
                        Alignment.centerRight,
                        progress,
                      )!,
                      child: Container(
                        key: const Key('turna-switch-thumb'),
                        width: 16 + progress * 4,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: TurnaTheme.textOnPrimary,
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 4px 近直角滑块游标（12×20 几何块）。
class TurnaSliderThumbShape extends SliderComponentShape {
  const TurnaSliderThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(12, 20);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final color = ColorTween(
      begin: sliderTheme.disabledThumbColor,
      end: sliderTheme.thumbColor,
    ).evaluate(enableAnimation)!;
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 12, height: 20),
        const Radius.circular(TurnaTheme.radius),
      ),
      Paint()..color = color,
    );
  }
}

/// 全局 4px 几何滑块。
class TurnaSlider extends StatelessWidget {
  const TurnaSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.activeColor,
    required this.inactiveColor,
    required this.onChanged,
    this.onChangeEnd,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: activeColor,
        inactiveTrackColor: inactiveColor,
        thumbColor: activeColor,
        disabledThumbColor: activeColor.withValues(alpha: 0.38),
        trackHeight: 4,
        trackShape: const RectangularSliderTrackShape(),
        thumbShape: const TurnaSliderThumbShape(),
        overlayShape: SliderComponentShape.noOverlay,
        tickMarkShape: SliderTickMarkShape.noTickMark,
      ),
      child: Slider(
        key: const Key('turna-slider'),
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}
