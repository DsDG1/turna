// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/views/settings/widgets/settings_about_section.dart';
import 'package:varnamala/views/settings/widgets/settings_account_section.dart';
import 'package:varnamala/views/settings/widgets/settings_appearance_section.dart';
import 'package:varnamala/views/settings/widgets/settings_common.dart';
import 'package:varnamala/views/settings/widgets/settings_learning_section.dart';
import 'package:varnamala/views/settings/widgets/settings_reminder_section.dart';
import 'package:varnamala/views/settings/widgets/settings_sound_section.dart';
import 'package:varnamala/views/theme.dart';

@RoutePage()
class SettingsPage extends StatelessWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          'Settings',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsSectionTitle(
                title: 'Account', icon: Icons.person_rounded),
            const SettingsAccountTile(),
            const SizedBox(height: 16),
            const SettingsSectionTitle(
                title: 'Learning', icon: Icons.menu_book_rounded),
            SettingsCard(
              children: [
                const SettingsLanguageSelectorTile(),
                settingsTileDivider(context),
                const SettingsTtsSpeedTile(),
                settingsTileDivider(context),
                const SettingsDailyReminderTile(),
              ],
            ),
            const SizedBox(height: 16),
            const SettingsSectionTitle(
                title: 'Sound & Haptics', icon: Icons.volume_up_rounded),
            SettingsCard(
              children: [
                SettingsToggleTile(
                  icon: Icons.music_note_rounded,
                  title: 'Sound effects',
                  subtitle: 'Play sounds for errors and level-ups',
                  valueSelector: (p) => p.soundEffectsEnabled,
                  onChanged: (p, value) => p.setSoundEffects(value),
                ),
                settingsTileDivider(context),
                SettingsToggleTile(
                  icon: Icons.vibration_rounded,
                  title: 'Haptic feedback',
                  subtitle: 'Vibrate on key interactions',
                  valueSelector: (p) => p.hapticFeedbackEnabled,
                  onChanged: (p, value) => p.setHapticFeedback(value),
                ),
                settingsTileDivider(context),
                const SettingsTtsEngineTile(),
              ],
            ),
            const SizedBox(height: 16),
            const SettingsSectionTitle(
                title: 'Appearance', icon: Icons.palette_rounded),
            const SettingsThemeSelector(),
            const SizedBox(height: 16),
            const SettingsSectionTitle(
                title: 'Data', icon: Icons.storage_rounded),
            SettingsCard(
              children: [
                SettingsActionTile(
                  icon: Icons.delete_sweep_rounded,
                  title: 'Clear mistake log',
                  subtitle: 'Remove all saved mistakes',
                  onTap: (context) => _confirmClearMistakes(context),
                ),
                settingsTileDivider(context),
                SettingsActionTile(
                  icon: Icons.restart_alt_rounded,
                  title: 'Reset lesson progress',
                  subtitle: 'Mark all lessons as not completed',
                  onTap: (context) => _confirmResetProgress(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SettingsSectionTitle(
                title: 'About', icon: Icons.info_rounded),
            const SettingsAboutSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearMistakes(BuildContext context) async {
    final mistakeProvider = context.read<MistakeProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const SettingsConfirmDialog(
        title: 'Clear mistake log?',
        message: 'This will permanently delete all saved mistakes.',
        confirmText: 'Clear',
      ),
    );
    if (confirmed == true) {
      await mistakeProvider.clear();
      if (context.mounted) {
        _showSnack(context, 'Mistake log cleared');
      }
    }
  }

  Future<void> _confirmResetProgress(BuildContext context) async {
    final gameProvider = context.read<GameProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const SettingsConfirmDialog(
        title: 'Reset lesson progress?',
        message: 'All lesson completion and perfect-lesson records will be '
            'cleared. This cannot be undone.',
        confirmText: 'Reset',
      ),
    );
    if (confirmed == true) {
      await gameProvider.resetLessonProgress();
      if (context.mounted) {
        _showSnack(context, 'Lesson progress reset');
      }
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
