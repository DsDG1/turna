// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/application/settings/settings_destination.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/pages/settings_category_body.dart';
import 'package:turna/views/settings/widgets/settings_accessibility_section.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';

/// Accessibility category page (formal route: `/settings/accessibility`).
@RoutePage()
class AccessibilitySettingsPage extends StatelessWidget {
  const AccessibilitySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: SettingsDestination.accessibility.title,
      body: SettingsCategoryBody(
        pageStorageKey: 'settings-accessibility',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSectionTitle(
              icon: Icons.accessibility_new_rounded,
              title: AppStrings.settingsA11ySectionTitle,
            ),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                const SettingsTextScaleTile(),
                settingsTileDivider(context),
                const SettingsCardTextScaleTile(),
                settingsTileDivider(context),
                const SettingsReducedMotionTile(),
                settingsTileDivider(context),
                const SettingsHighContrastTile(),
                settingsTileDivider(context),
                const SettingsDyslexiaFontTile(),
                settingsTileDivider(context),
                const SettingsSensoryReduceTile(),
                settingsTileDivider(context),
                const SettingsFocusModeTile(),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
