// Flutter imports:
import 'package:flutter/material.dart';

/// Stub app bar so the Settings tab's [HomePage] AppBar slot stays indexed
/// (appBars has one entry per tab) while the actual Settings app bar is owned
/// by the nested `Scaffold` inside [SettingsPage]. This avoids a double AppBar
/// now that Settings navigates category sub-pages with its own back button.
///
/// The outer Scaffold positions its body below the app bar's *measured*
/// height (not `preferredSize`), and strips the top padding from the body's
/// MediaQuery when an app bar is present. So this stub must really occupy the
/// reserved space: `preferredSize` is zero and the outer Scaffold adds the
/// status-bar padding on top, while the widget below expands to fill it. That
/// pushes the inner Settings AppBar below the status bar, at the same height
/// as the other tabs' titles.
class SettingsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SettingsAppBar({super.key});

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}