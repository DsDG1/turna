// 设置域控件兼容入口：ADR 0075 将设置域局部方形主题并入全局 4px 规则，
// 开关与滑块统一复用 `lib/views/widgets/turna_controls.dart`。
import 'package:flutter/material.dart';

import 'package:turna/views/widgets/turna_controls.dart';

export 'package:turna/views/widgets/turna_controls.dart'
    show TurnaSlider, TurnaSliderThumbShape, TurnaSwitch;

typedef SettingsSquareSwitch = TurnaSwitch;
typedef SettingsSquareSlider = TurnaSlider;
typedef SettingsSquareSliderThumbShape = TurnaSliderThumbShape;

/// 保留兼容占位：全局 [TurnaTheme] 已统一所有按钮族为 4px，不再做局部覆写。
class SettingsSquareControlTheme extends StatelessWidget {
  const SettingsSquareControlTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
