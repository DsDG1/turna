// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/application/settings/settings_destination.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/pages/settings_category_body.dart';
import 'package:turna/views/settings/widgets/settings_appearance_section.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/settings/widgets/settings_sound_section.dart';

/// Appearance & sound category page (formal route:
/// `/settings/appearance-sound`).
@RoutePage()
class AppearanceSoundSettingsPage extends StatelessWidget {
  const AppearanceSoundSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: SettingsDestination.appearanceAndSound.title,
      body: SettingsCategoryBody(
        pageStorageKey: 'settings-appearance-sound',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSectionTitle(
              icon: Icons.palette_rounded,
              title: AppStrings.settingsAppearanceSectionTitle,
            ),
            const SizedBox(height: 8),
            const SettingsThemeSelector(),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsToggleTile(
                  icon: Icons.screen_rotation_rounded,
                  title: AppStrings.settingsAutoRotateTitle,
                  subtitle: AppStrings.settingsAutoRotateSubtitle,
                  valueSelector: (p) => p.autoRotateEnabled,
                  onChanged: (p, value) => p.setAutoRotateEnabled(value),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SettingsSectionTitle(
              icon: Icons.volume_up_rounded,
              title: AppStrings.settingsAudioSectionTitle,
            ),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsToggleTile(
                  icon: Icons.music_note_rounded,
                  title: AppStrings.settingsSoundEffectsTitle,
                  subtitle: AppStrings.settingsSoundEffectsSubtitle,
                  valueSelector: (p) => p.soundEffectsEnabled,
                  onChanged: (p, value) => p.setSoundEffects(value),
                ),
                settingsTileDivider(context),
                SettingsToggleTile(
                  icon: Icons.vibration_rounded,
                  title: AppStrings.settingsHapticFeedbackTitle,
                  subtitle: AppStrings.settingsHapticFeedbackSubtitle,
                  valueSelector: (p) => p.hapticFeedbackEnabled,
                  onChanged: (p, value) => p.setHapticFeedback(value),
                ),
                settingsTileDivider(context),
                const SettingsTtsEngineTile(),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
