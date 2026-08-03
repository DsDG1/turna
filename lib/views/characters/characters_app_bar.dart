// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/core/extensions.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/theme.dart';

class CharactersAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CharactersAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      centerTitle: true,
      title: PreferenceBuilder<String>(
        preference: getIt<AppPrefs>().currentLanguage,
        builder: (context, currentLanguage) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.translate_rounded,
                  color: TurnaTheme.peacockTeal, size: 22),
              const SizedBox(width: 8),
              Text(
                AppStrings.charactersScriptTitle(currentLanguage.toTitleCase),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
