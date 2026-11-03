/// 文字导航 ——「湿地雾光」外壳的下半件（P2 组件，P3 外壳重构接线）。
///
/// R01 决定：底部水平**文字**导航 + 受光短条（16×4 芦苇青）标记当前
/// Tab，替代旧版图标 + 文字 + 滑动镜片的胶囊导航。选中态靠文字色重 +
/// 短条双信号，高对比下短条即形状信号；未选中项保持可读的次级色。
///
/// 滚动显隐（ScrollHideBar）与 TabStack 状态保留由外壳在接线时决定是否
/// 沿用——本组件只保证自身是静态、无持续动画的面。
library;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// Project imports:
import 'package:turna/core/theme.dart';

/// 一个文字导航目的地。
class TextTabItem {
  const TextTabItem({required this.label, this.tooltip});

  final String label;

  /// 语义名（与屏幕阅读器朗读稿一致）；缺省用 [label]。
  final String? tooltip;
}

/// 底部文字导航条。
class TextTabBar extends StatelessWidget {
  const TextTabBar({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    super.key,
  });

  final List<TextTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  /// 内容高度（不含安全区）。接线时 body 的 overlay padding 以此为基线。
  static const double contentHeight = 64;

  @override
  Widget build(BuildContext context) {
    // 文字放大时封顶 1.4：导航是固定件，不随 200% 字号无限撑高。
    final scale = MediaQuery.textScalerOf(context)
        .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.4);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        border: Border(
          top: BorderSide(color: TurnaTheme.dividerBg(context)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: contentHeight,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _TextTabButton(
                    item: items[i],
                    selected: i == selectedIndex,
                    textScaler: scale,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextTabButton extends StatelessWidget {
  const _TextTabButton({
    required this.item,
    required this.selected,
    required this.textScaler,
    required this.onTap,
  });

  final TextTabItem item;
  final bool selected;
  final TextScaler textScaler;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: item.tooltip ?? item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 受光短条：始终占位，未选中画透明——切 Tab 时文字基线不动。
            Container(
              width: 16,
              height: 4,
              decoration: ShapeDecoration(
                color: selected
                    ? TurnaTheme.brandReed
                    : Colors.transparent,
                shape: const StadiumBorder(),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              item.label,
              textScaler: textScaler,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? TurnaTheme.brandTeal
                    : TurnaTheme.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

@Preview(name: 'Text tab bar · light', group: 'Wetland mist')
@Preview(
    name: 'Text tab bar · dark',
    group: 'Wetland mist',
    brightness: Brightness.dark)
Widget textTabBarPreview() => const Scaffold(
      body: Column(
        children: [
          Expanded(child: SizedBox()),
          TextTabBar(
            items: [
              TextTabItem(label: '学习'),
              TextTabItem(label: '练习'),
              TextTabItem(label: '我的'),
              TextTabItem(label: '设置'),
            ],
            selectedIndex: 1,
            onTap: _noop,
          ),
        ],
      ),
    );

void _noop(int index) {}
