// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/theme.dart';

class PlayAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PlayAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      centerTitle: true,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.extension_rounded,
            color: VarnamalaTheme.peacockTeal,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(
            AppStrings.playTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
