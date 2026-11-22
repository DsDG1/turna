/// 全 App 包豪斯几何 SVG 图标渲染器（ADR 0075）。
///
/// 统一消费 [TurnaIconId] 与 `assets/icons/*.svg`，替代 Material `Icons.*`。
/// 自动继承 [IconTheme] 的字号与前景色；SVG 内置几何半透明色块会随
/// `BlendMode.srcIn` 同步染成语义色，浅色 / 深色 / 高对比模式下均保持清晰。
library;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// Package imports:
import 'package:flutter_svg/flutter_svg.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';

class TurnaIcon extends StatelessWidget {
  const TurnaIcon(
    this.id, {
    this.size,
    this.color,
    this.semanticLabel,
    super.key,
  });

  final TurnaIconId id;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24.0;
    final resolvedColor =
        color ?? iconTheme.color ?? TurnaTheme.textPrimaryColor(context);

    final svg = SvgPicture.asset(
      id.assetPath,
      width: resolvedSize,
      height: resolvedSize,
      fit: BoxFit.contain,
      excludeFromSemantics: semanticLabel == null,
      semanticsLabel: semanticLabel,
      colorFilter: ColorFilter.mode(resolvedColor, BlendMode.srcIn),
    );

    if (semanticLabel == null) return svg;
    return Semantics(label: semanticLabel, child: svg);
  }
}

@Preview(name: 'Turna icons · light', group: 'Wetland mist')
@Preview(
  name: 'Turna icons · dark',
  group: 'Wetland mist',
  brightness: Brightness.dark,
)
Widget turnaIconPreview() => const Wrap(
  spacing: 16,
  runSpacing: 16,
  children: [
    TurnaIcon(TurnaIconId.book, color: TurnaTheme.brandTeal),
    TurnaIcon(TurnaIconId.play, color: TurnaTheme.brandTeal),
    TurnaIcon(TurnaIconId.flame, color: TurnaTheme.anatolianClay),
    TurnaIcon(TurnaIconId.spark, color: TurnaTheme.brandSky),
    TurnaIcon(TurnaIconId.trophy, color: TurnaTheme.anatolianClay),
    TurnaIcon(TurnaIconId.checkCircle, color: TurnaTheme.brandTeal),
  ],
);
