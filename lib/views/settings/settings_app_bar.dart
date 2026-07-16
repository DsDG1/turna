// Flutter imports:
import 'package:flutter/material.dart';

/// Zero-height stub so the Settings tab's [HomePage] AppBar slot stays indexed
/// (appBars has one entry per tab) while the actual Settings app bar is owned
/// by the nested `Scaffold` inside [SettingsPage]. This avoids a double AppBar
/// now that Settings navigates category sub-pages with its own back button.
class SettingsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SettingsAppBar({super.key});

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}