// Flutter imports:
import 'package:flutter/material.dart';

/// Stub app bar for the AI Hub tab. The Hub page itself is a `CustomScrollView`
/// with no internal Scaffold, so the outer HomePage AppBar slot is filled with
/// a zero-height widget (mirrors `SettingsAppBar`). Keeps the `appBars` list
/// in [HomePage] aligned with the bottom-nav tile count.
class AiHubAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AiHubAppBar({super.key});

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}