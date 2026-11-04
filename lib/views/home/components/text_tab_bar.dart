/// 文字导航 ——「湿地雾光」外壳的下半件（P2 组件，P3 外壳重构接线）。
///
/// R01 决定：底部水平**文字**导航 + 受光短条（16×4 芦苇青）标记当前
/// Tab，替代旧版图标 + 文字 + 滑动镜片的胶囊导航。选中态靠文字色重 +
/// 短条双信号，高对比下短条即形状信号；未选中项保持可读的次级色。
///
/// 外壳是浮在滚动内容之上的磨砂胶囊：离底、左右留边、圆角、单层阴影 +
/// 轻量背景模糊。滚动显隐（ScrollHideBar）与 TabStack 状态保留由外壳
/// 接线决定；本组件自身仍是静态、无持续动画的面。
library;

// Dart imports:
import 'dart:ui' show ImageFilter;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
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

  /// 胶囊内容高度（不含安全区与外边距）。
  static const double contentHeight = 64;

  /// 胶囊左右留边 / 离底间隙 / 顶部给阴影留的空间。
  static const double sideInset = 16;
  static const double bottomGap = 8;
  static const double topShadowPad = 8;
  static const double capsuleRadius = TurnaTheme.radiusXLarge;

  /// body 避让高度：胶囊相对系统手势区额外占用的高度。
  ///
  /// **不含系统 inset** —— `home_page.dart` 的 `mq.padding.bottom` 已带上；
  /// 含 [topShadowPad] 是为了让滚动内容不贴到胶囊与阴影边缘。
  static const double overlayExtent = contentHeight + bottomGap + topShadowPad;

  /// 轻量背景模糊强度，刻意低于 `TurnaSnackBar.frostSigma`(16)：底部条是
  /// 全宽 64px 窄条、背后是持续滚动的列表，每帧都要 backdrop 采样，sigma 16
  /// 会让 13px 标签发糊且更费 GPU；SnackBar 是短时、小面积、基本静止的气泡，
  /// 16 仍合适。两者不追求同一数值。
  static const double frostSigma = 8.0;

  @override
  Widget build(BuildContext context) {
    // Scaffold 传给 bottomNavigationBar 的 MediaQuery 保留底部 padding
    // （removeBottomPadding: false），这里只吃一次 inset，不再套 SafeArea。
    // 用 paddingOf 而非 viewPaddingOf：键盘弹出时它归零，与 body 的避让
    // 同步收缩；旧胶囊用 viewPaddingOf 在键盘场景会与 body 差一截。
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // 文字放大时封顶 1.4：导航是固定件，不随 200% 字号无限撑高。
    final scale = MediaQuery.textScalerOf(context)
        .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.4);
    // 可空 read：widget 预览与单测里没挂 Provider，不能抛。
    final a11y = context.read<AccessibilityProvider?>();
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        (a11y?.reducedMotion ?? false);
    final solidGlass =
        (a11y?.highContrast ?? false) || (a11y?.focusMode ?? false);

    final radius = BorderRadius.circular(capsuleRadius);
    final fill = solidGlass
        ? TurnaTheme.bottomNavBg(context)
        : TurnaTheme.floatingBarFill(context);

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(
          color: solidGlass
              ? TurnaTheme.statCardBorder(context)
              : TurnaTheme.glassBorder(context),
          width: solidGlass ? 1.5 : 1.0,
        ),
      ),
      // InkWell 的宿主：水波纹画在这一层，才不会被半透明面与滤镜层挡住。
      child: Material(
        type: MaterialType.transparency,
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

    return Padding(
      padding: EdgeInsets.fromLTRB(
        sideInset,
        topShadowPad,
        sideInset,
        bottomGap + bottomInset,
      ),
      // 阴影必须在 ClipRRect 之外，否则会被圆角裁掉。
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: TurnaTheme.floatingBarShadow(context),
        ),
        // 隔离每帧的 backdrop 采样，避免牵连整页重绘。
        child: RepaintBoundary(
          child: ClipRRect(
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: solidGlass || reduceMotion
                ? surface
                : BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: frostSigma,
                      sigmaY: frostSigma,
                    ),
                    child: surface,
                  ),
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
                color: selected ? TurnaTheme.brandReed : Colors.transparent,
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
