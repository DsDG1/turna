// Flutter imports:
import 'package:flutter/material.dart';

/// Stub app bar so the Settings tab's [HomePage] AppBar slot stays indexed
/// (appBars has one entry per tab) while the actual Settings app bar is owned
/// by the nested `Scaffold` inside [SettingsPage]. This avoids a double AppBar
/// now that Settings navigates category sub-pages with its own back button.
/// The preferred height matches a standard AppBar (56) so the outer Scaffold
/// reserves space for the status bar.
class SettingsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SettingsAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    // Zero-height stub: the actual Settings app bar lives inside SettingsPage's
    // own Scaffold. We return a non-zero preferredSize here so the outer
    // HomePage Scaffold reserves space for the status bar and the content
    // doesn't overlap it.
    return const SizedBox.shrink();
  }
}