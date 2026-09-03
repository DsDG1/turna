// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/settings/commands/reset_learning_settings_command.dart';
import 'package:turna/application/settings/settings_destination.dart';
import 'package:turna/application/settings/settings_operation_result.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/pages/settings_category_body.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/settings/widgets/settings_learning_section.dart';
import 'package:turna/views/settings/widgets/settings_reminder_section.dart';
import 'package:turna/views/settings/widgets/settings_sound_section.dart';

/// Learning category page (formal route: `/settings/learning`).
///
/// The reset-learning-defaults action runs through
/// [ResetLearningSettingsCommand]; its [ResetLearningSettingsCommand.notResetScopes]
/// list is rendered in the confirmation dialog so the UI promise and the
/// implementation cannot drift apart. A local epoch rebuilds the Anki limit
/// sliders after a reset (those values are owned by AnkiDeckManager, not
/// SettingsProvider).
@RoutePage()
class LearningSettingsPage extends StatefulWidget {
  const LearningSettingsPage({super.key});

  @override
  State<LearningSettingsPage> createState() => _LearningSettingsPageState();
}

class _LearningSettingsPageState extends State<LearningSettingsPage> {
  int _ankiEpoch = 0;

  Future<void> _confirmResetLearningDefaults(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettingsConfirmDialog(
        title: AppStrings.settingsResetLearningDefaultsDialogTitle,
        message: '${AppStrings.settingsResetLearningDefaultsDialogMessage}\n\n'
            '不会清除：\n'
            '${ResetLearningSettingsCommand.notResetScopes.map((s) => '· $s').join('\n')}',
        confirmText: AppStrings.settingsResetLearningDefaultsConfirm,
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await getIt<ResetLearningSettingsCommand>().execute();
    if (!context.mounted) return;
    switch (result) {
      case SettingsOperationSuccess():
        setState(() => _ankiEpoch++);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.settingsResetLearningDefaultsDone)),
        );
      case SettingsOperationFailure(:final userMessage):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessage)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: SettingsDestination.learning.title,
      body: SettingsCategoryBody(
        pageStorageKey: 'settings-learning',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSectionTitle(
              icon: Icons.tune_rounded,
              title: AppStrings.settingsLearningPrefsTitle,
            ),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                const SettingsLanguageSelectorTile(),
                settingsTileDivider(context),
                SettingsToggleTile(
                  icon: Icons.record_voice_over_rounded,
                  title: AppStrings.settingsTtsFeatureTitle,
                  subtitle: AppStrings.settingsTtsFeatureSubtitle,
                  valueSelector: (p) => p.ttsFeatureEnabled,
                  onChanged: (p, v) => p.setTtsFeatureEnabled(v),
                ),
                _TtsSpeedGate(),
                settingsTileDivider(context),
                const SettingsSrsRetentionTile(),
                settingsTileDivider(context),
                const SettingsSrsWeightsTile(),
                settingsTileDivider(context),
                const SettingsDailyReminderTile(),
                settingsTileDivider(context),
                const SettingsStreakVoucherAutoUseTile(),
              ],
            ),
            const SizedBox(height: 20),
            SettingsSectionTitle(
              icon: Icons.style_rounded,
              title: AppStrings.settingsAnkiSectionTitle,
            ),
            const SizedBox(height: 8),
            SettingsCard(
              key: ValueKey('anki-prefs-$_ankiEpoch'),
              children: [
                const SettingsAnkiNewLimitTile(),
                settingsTileDivider(context),
                const SettingsAnkiReviewLimitTile(),
                settingsTileDivider(context),
                const SettingsDailyChallengeAnkiTile(),
              ],
            ),
            const SizedBox(height: 12),
            SettingsCard(
              children: [
                SettingsActionTile(
                  icon: Icons.restart_alt_rounded,
                  title: AppStrings.settingsResetLearningDefaultsTitle,
                  subtitle: AppStrings.settingsResetLearningDefaultsSubtitle,
                  onTap: (context) => _confirmResetLearningDefaults(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// TTS speed only exists while the read-aloud master switch is on — same
/// show/hide pattern as the daily-reminder time row. The divider travels
/// with the tile so a hidden tile never leaves a double divider behind.
class _TtsSpeedGate extends StatelessWidget {
  const _TtsSpeedGate();

  @override
  Widget build(BuildContext context) {
    final enabled = context.select<SettingsProvider, bool>(
      (p) => p.ttsFeatureEnabled,
    );
    if (!enabled) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        settingsTileDivider(context),
        const SettingsTtsSpeedTile(),
      ],
    );
  }
}
