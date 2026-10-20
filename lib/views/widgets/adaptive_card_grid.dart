// Flutter imports:
import 'package:flutter/material.dart';

/// 行高自适应网格：列宽由 [columns] 均分，每行高度由该行最高的卡片决定。
///
/// 为什么不用 `GridView.count(childAspectRatio: ...)`：宽高比是**固定像素**
/// 契约 —— 系统字体放大后卡片里的文字长高，格子高度却不变，于是 RenderFlex
/// 报 `BOTTOM OVERFLOWED BY n PIXELS`。`SliverGridDelegate.mainAxisExtent`
/// 也只在构建期取常量，同样拿不到「放大后的真实行高」。
///
/// 这里改用 `Row` + [IntrinsicHeight]：行高 = 该行内容高度，字体放大多少
/// 卡片就长多高；`CrossAxisAlignment.stretch` 保证同行卡片等高，剩下的
/// 竖直空间由卡片内的 `Spacer` / `MainAxisAlignment` 吸收。
///
/// 旧版格子的「常规字号下应该多高」由两个可选参数声明，二者都不改变放大后
/// 的自适应行为，只提供高度下限：
/// - [minChildAspectRatio]：等价于原来的 `childAspectRatio`，高度随列宽走；
/// - [minChildHeight]：等价于原来的固定 `SizedBox(height:)`，高度不随列宽走。
class AdaptiveCardGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  final double spacing;

  /// 单格最小宽高比（宽 / 高），与 `GridView.childAspectRatio` 同口径。
  final double? minChildAspectRatio;

  /// 单格最小高度（逻辑像素），与旧版固定高度同口径。
  final double? minChildHeight;

  const AdaptiveCardGrid({
    super.key,
    required this.children,
    this.columns = 2,
    this.spacing = 12,
    this.minChildAspectRatio,
    this.minChildHeight,
  })  : assert(columns > 0),
        assert(minChildAspectRatio == null || minChildAspectRatio > 0),
        assert(minChildHeight == null || minChildHeight >= 0);

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = _resolveMinHeight(constraints.maxWidth);
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          final cells = <Widget>[];
          for (var column = 0; column < columns; column++) {
            final index = start + column;
            if (column > 0) cells.add(SizedBox(width: spacing));
            cells.add(
              Expanded(
                child: index < children.length
                    ? ConstrainedBox(
                        constraints: BoxConstraints(minHeight: minHeight),
                        child: children[index],
                      )
                    : const SizedBox.shrink(),
              ),
            );
          }
          if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells,
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  double _resolveMinHeight(double maxWidth) {
    final fixed = minChildHeight;
    if (fixed != null) return fixed;
    final ratio = minChildAspectRatio;
    if (ratio == null) return 0;
    final cellWidth = (maxWidth - spacing * (columns - 1)) / columns;
    return cellWidth <= 0 ? 0 : cellWidth / ratio;
  }
}
