// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/local_reminder_service.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/settings/widgets/settings_sound_section.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

class SettingsDailyReminderTile extends StatelessWidget {
  const SettingsDailyReminderTile({super.key});

  Future<void> _syncReminder(SettingsProvider settings) async {
    await getIt<LocalReminderService>().applyFromSettings(
      enabled: settings.dailyReminderEnabled,
      time: settings.dailyReminderTime,
    );
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
          onChanged: (p, value) async {
            await p.setDailyReminderEnabled(value);
            await _syncReminder(p);
          },
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
                    color: TurnaTheme.peacockTeal,
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
              await settings.setDailyReminderTime(picked);
              await _syncReminder(settings);
            },
          ),
        ],
      ],
    );
  }
}
