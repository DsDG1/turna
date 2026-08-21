// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/theme_provider.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/turna_select.dart';

class SettingsThemeSelector extends StatelessWidget {
  const SettingsThemeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final current = themeProvider.themeMode;

    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: TurnaSegmented<ThemeMode>(
            selected: current,
            onChanged: themeProvider.setThemeMode,
            segments: [
              ButtonSegment(
                value: ThemeMode.light,
                label: Text(AppStrings.settingsThemeLight),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text(AppStrings.settingsThemeDark),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                label: Text(AppStrings.settingsThemeSystem),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
