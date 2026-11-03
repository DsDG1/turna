// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/theme.dart';

/// 练习 Tab 的顶栏占位（「湿地雾光」R07）。
///
/// 练习页页头（「练习」pageTitle + 日期 captionSm）已移入页面正文（见
/// `play_hub_screen.dart` 的开篇），顶栏不再承载标题，只保留高度占位：
/// `SafeArea` + [TurnaTheme.tabAppBarHeight] 的透明条，让四个根 Tab 的
/// 内容起点与基线和 Learn / Profile 一致（高度契约见
/// `test/views/tab_app_bar_contract_test.dart`）。
class PlayAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PlayAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(TurnaTheme.tabAppBarHeight);

  @override
  Widget build(BuildContext context) {
    // 透明占位：背景由 HomePage 外层 AnimatedContainer 的表面色透出。
    return const SafeArea(
      bottom: false,
      child: SizedBox(height: TurnaTheme.tabAppBarHeight),
    );
  }
}
