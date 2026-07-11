// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/service/local_reminder_service.dart';
import 'package:varnamala/views/settings/widgets/settings_common.dart';
import 'package:varnamala/views/settings/widgets/settings_sound_section.dart';
import 'package:varnamala/views/theme.dart';

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
    final settings = context.watch<SettingsProvider>();
    final enabled = settings.dailyReminderEnabled;
    final time = settings.dailyReminderTime;
    final timeLabel =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Column(
      children: [
        SettingsToggleTile(
          icon: Icons.notifications_active_outlined,
          title: 'Daily reminder',
          subtitle: 'Gentle nudge to review — no streaks or penalties',
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
            title: 'Reminder time',
            subtitle: 'Currently $timeLabel',
            trailing: Text(
              timeLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: VarnamalaTheme.peacockTeal,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: time,
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
