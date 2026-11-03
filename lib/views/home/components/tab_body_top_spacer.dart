// Flutter imports:
import 'package:flutter/material.dart';

/// Profile / Settings Tab 的顶栏占位（「湿地雾光」R15 / R16）。
///
/// 两个 Tab 的页头已改为**页内** `pageTitle` 开篇，不再有 Tab 级 AppBar
/// （`ProfileAppBar` / `SettingsAppBar` 退役；积分与宝石回到个人页的学习
/// 积累区）。本占位让 [HomePage] 的 appBars 数组保持每 Tab 一项，同时只
/// 占住状态栏高度：
///
/// - `preferredSize` 为零，外层 Scaffold 会在其上叠加状态栏 padding；
/// - [SizedBox.expand] 填满实测高度（状态栏条），body 从状态栏下方开始；
/// - 外层 Scaffold 有 AppBar 时会剥掉 body MediaQuery 的顶部 padding，所以
///   页内 `pageTitle` 无需再补 `SafeArea` 顶距。
///
/// 深页（push 出去的路由页）仍各自持有带返回键的 AppBar，不受本件影响。
class TabBodySpacer extends StatelessWidget implements PreferredSizeWidget {
  const TabBodySpacer({super.key});

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}
