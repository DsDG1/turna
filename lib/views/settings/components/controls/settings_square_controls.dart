import 'package:flutter/material.dart';

import 'package:turna/core/motion.dart';
import 'package:turna/core/theme.dart';

const _squareShape = RoundedRectangleBorder(borderRadius: BorderRadius.zero);

ButtonStyle _squareButtonStyle(ButtonStyle? style) {
  const shape = WidgetStatePropertyAll<OutlinedBorder>(_squareShape);
  return style?.copyWith(shape: shape) ?? const ButtonStyle(shape: shape);
}

ThemeData _squareControlTheme(BuildContext context) {
  final theme = Theme.of(context);
  return theme.copyWith(
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _squareButtonStyle(theme.elevatedButtonTheme.style),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _squareButtonStyle(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _squareButtonStyle(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _squareButtonStyle(theme.textButtonTheme.style),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: _squareButtonStyle(theme.iconButtonTheme.style),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: _squareButtonStyle(theme.segmentedButtonTheme.style),
    ),
  );
}

class SettingsSquareControlTheme extends StatelessWidget {
  const SettingsSquareControlTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(data: _squareControlTheme(context), child: child);
  }
}

class SettingsSquareSwitch extends StatelessWidget {
  const SettingsSquareSwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

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
      key: const Key('settings-square-switch'),
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
                duration: TurnaMotion.scaled(
                  TurnaMotion.fast,
                  reduceMotion,
                ),
                curve: TurnaMotion.easeOut,
                builder: (context, progress, _) {
                  return Container(
                    key: const Key('settings-square-switch-track'),
                    width: 48,
                    height: 28,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: value
                          ? TurnaTheme.brandTeal
                          : TurnaTheme.dividerBg(context),
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
                        key: const Key('settings-square-switch-thumb'),
                        width: 16 + progress * 4,
                        height: 20,
                        color: TurnaTheme.textOnPrimary,
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

class SettingsSquareSliderThumbShape extends SliderComponentShape {
  const SettingsSquareSliderThumbShape();

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
    context.canvas.drawRect(
      Rect.fromCenter(center: center, width: 12, height: 20),
      Paint()..color = color,
    );
  }
}

class SettingsSquareSlider extends StatelessWidget {
  const SettingsSquareSlider({
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
        thumbShape: const SettingsSquareSliderThumbShape(),
        overlayShape: SliderComponentShape.noOverlay,
        tickMarkShape: SliderTickMarkShape.noTickMark,
      ),
      child: Slider(
        key: const Key('settings-square-slider'),
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
