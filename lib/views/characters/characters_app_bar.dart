// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:varnamala/core/extensions.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/l10n/app_localizations.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/views/theme.dart';

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
                  color: VarnamalaTheme.peacockTeal, size: 22),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!
                    .charactersScriptTitle(currentLanguage.toTitleCase),
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
