// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/settings/commands/update_daily_reminder_command.dart';
import 'package:turna/application/settings/settings_operation_result.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/settings/widgets/settings_sound_section.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Daily reminder toggle + time picker. All changes go through
/// [UpdateDailyReminderCommand]: the OS schedule is applied first and the
/// preference is only committed when scheduling succeeds, so the toggle can
/// never display "enabled" for a reminder the system refused to schedule.
class SettingsDailyReminderTile extends StatelessWidget {
  const SettingsDailyReminderTile({super.key});

  Future<void> _apply(
    BuildContext context, {
    required bool enabled,
    TimeOfDay? time,
  }) async {
    final result = await getIt<UpdateDailyReminderCommand>()
        .execute(enabled: enabled, time: time);
    if (!context.mounted) return;
    if (result is SettingsOperationFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.userMessage)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Narrow selects: avoid rebuilding this whole block on unrelated settings
    // (e.g. TTS speed) while still showing/hiding the time row correctly.
    final enabled = context.select<SettingsProvider, bool>(
      (p) => p.dailyReminderEnabled,
    );
    final timeLabel = context.select<SettingsProvider, String>((p) {
      final t = p.dailyReminderTime;
      return '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
    });

    return Column(
      children: [
        SettingsToggleTile(
          icon: Icons.notifications_active_outlined,
          title: AppStrings.settingsDailyReminderTitle,
          subtitle: AppStrings.settingsDailyReminderSubtitle,
          valueSelector: (p) => p.dailyReminderEnabled,
          onChanged: (p, value) => _apply(context, enabled: value),
        ),
        if (enabled) ...[
          settingsTileDivider(context),
          SettingsTile(
            icon: Icons.schedule_rounded,
            title: AppStrings.settingsReminderTimeTitle,
            subtitle: AppStrings.settingsReminderTimeSubtitle(timeLabel),
            trailing: Text(
              timeLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.brandTeal,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            onTap: () async {
              final settings = context.read<SettingsProvider>();
              final picked = await showTimePicker(
                context: context,
                initialTime: settings.dailyReminderTime,
              );
              if (picked == null) return;
              if (!context.mounted) return;
              await _apply(context, enabled: true, time: picked);
            },
          ),
        ],
      ],
    );
  }
}
