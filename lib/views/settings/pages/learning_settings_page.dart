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
import 'package:turna/core/ohos_target.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/components/settings_course_restore_tile.dart';
import 'package:turna/views/settings/components/settings_course_update_tile.dart';
import 'package:turna/views/settings/pages/settings_category_body.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/settings/widgets/settings_learning_section.dart';
import 'package:turna/views/settings/widgets/settings_reminder_section.dart';
import 'package:turna/views/settings/widgets/settings_sound_section.dart';
import 'package:turna/views/widgets/turna_sheet.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// Learning category page (formal route: `/settings/learning`).
///
/// The reset-learning-defaults action runs through
/// [ResetLearningSettingsCommand]; its [ResetLearningSettingsCommand.notResetScopes]
/// list is rendered in the confirmation dialog so the UI promise and the
/// implementation cannot drift apart.
///
/// Anki 每日上限（新卡 / 复习 / 每日挑战并入）在记忆卡复习页
/// （`AnkiReviewPage`）设置，不出现在语言课程的设置页（ADR 0067）。
@RoutePage()
class LearningSettingsPage extends StatefulWidget {
  const LearningSettingsPage({super.key});

  @override
  State<LearningSettingsPage> createState() => _LearningSettingsPageState();
}

class _LearningSettingsPageState extends State<LearningSettingsPage> {
  Future<void> _confirmResetLearningDefaults(BuildContext context) async {
    final confirmed = await showTurnaConfirmDialog(
      context: context,
      title: AppStrings.settingsResetLearningDefaultsDialogTitle,
      message: '${AppStrings.settingsResetLearningDefaultsDialogMessage}\n\n'
          '${AppStrings.settingsResetLearningKeptScopes(ResetLearningSettingsCommand.notResetScopes)}',
      confirmLabel: AppStrings.settingsResetLearningDefaultsConfirm,
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;

    final result = await getIt<ResetLearningSettingsCommand>().execute();
    if (!context.mounted) return;
    switch (result) {
      case SettingsOperationSuccess():
        TurnaSnackBar.show(
            context, AppStrings.settingsResetLearningDefaultsDone);
      case SettingsOperationFailure(:final userMessage):
        TurnaSnackBar.show(context, userMessage);
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
                const SettingsCourseUpdateTile(),
                settingsTileDivider(context),
                const SettingsCourseRestoreTile(),
                settingsTileDivider(context),
                SettingsToggleTile(
                  icon: Icons.record_voice_over_rounded,
                  title: AppStrings.settingsTtsFeatureTitle,
                  subtitle: AppStrings.settingsTtsFeatureSubtitle,
                  valueSelector: (p) => p.ttsFeatureEnabled,
                  onChanged: (p, v) => p.setTtsFeatureEnabled(v),
                ),
                const _TtsSpeedGate(),
                settingsTileDivider(context),
                const _ReadAloudGate(),
                settingsTileDivider(context),
                const SettingsSrsRetentionTile(),
                settingsTileDivider(context),
                const SettingsReviewBatchTile(),
                settingsTileDivider(context),
                const SettingsSrsWeightsTile(),
                settingsTileDivider(context),
                const SettingsDailyReminderTile(),
                settingsTileDivider(context),
                const SettingsStreakVoucherAutoUseTile(),
              ],
            ),
            const SizedBox(height: 20),
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

/// 跟读 (mic recognition) master switch, ADR 0061. Hidden entirely on builds
/// without a recognizer (the companion build) — a toggle that cannot work is
/// worse than an absent one. The divider travels with the tile, same as
/// [_TtsSpeedGate].
class _ReadAloudGate extends StatelessWidget {
  const _ReadAloudGate();

  @override
  Widget build(BuildContext context) {
    if (isDegraded(OhosDegradation.readAloud)) return const SizedBox.shrink();
    return SettingsToggleTile(
      icon: Icons.mic_rounded,
      title: AppStrings.settingsReadAloudTitle,
      subtitle: AppStrings.settingsReadAloudSubtitle,
      valueSelector: (p) => p.readAloudExercisesEnabled,
      onChanged: (p, v) => p.setReadAloudExercisesEnabled(v),
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
