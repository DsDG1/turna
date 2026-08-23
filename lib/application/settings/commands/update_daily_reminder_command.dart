// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/settings/settings_operation_result.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/local_reminder_service.dart';

/// Applies a daily-reminder change end to end: validates the time, applies
/// the OS notification schedule FIRST, and only after it succeeds commits
/// the preference so the UI can never show "enabled" for a reminder the
/// system refused to schedule. On failure the previous preference state is
/// restored and a retryable failure is returned.
class UpdateDailyReminderCommand {
  const UpdateDailyReminderCommand();

  Future<SettingsOperationResult> execute({
    required bool enabled,
    TimeOfDay? time,
  }) async {
    final hour = time?.hour;
    final minute = time?.minute;
    if (hour != null && (hour < 0 || hour > 23)) {
      return const SettingsOperationFailure(
        code: 'reminder.invalidTime',
        userMessage: '提醒时间无效。',
      );
    }
    if (minute != null && (minute < 0 || minute > 59)) {
      return const SettingsOperationFailure(
        code: 'reminder.invalidTime',
        userMessage: '提醒时间无效。',
      );
    }

    final settings = getIt<SettingsProvider>();
    final previousEnabled = settings.dailyReminderEnabled;
    final previousTime = settings.dailyReminderTime;
    final service = getIt<LocalReminderService>();

    // Snapshot of the old schedule state is implicit: re-applying the old
    // settings below restores it. Schedule the NEW state first…
    try {
      await service.applyFromSettings(
        enabled: enabled,
        time: time ?? previousTime,
      );
    } on Object catch (error) {
      // Scheduling failed: the stored preference is untouched, so displayed
      // state ("off" or the old time) still matches reality.
      return SettingsOperationFailure(
        code: 'reminder.scheduleFailed',
        userMessage: '提醒调度失败，设置未保存。请检查通知权限后重试。'
            '（${_sanitize(error)}）',
        retryable: true,
      );
    }

    // …commit the preference only after the schedule succeeded.
    try {
      await settings.setDailyReminderEnabled(enabled);
      if (time != null) {
        await settings.setDailyReminderTime(time);
      }
    } on Object catch (error) {
      // Preference write failed after scheduling: reschedule the previous
      // state so prefs and OS stay consistent.
      try {
        await service.applyFromSettings(
          enabled: previousEnabled,
          time: previousTime,
        );
      } catch (_) {
        // Best effort — return the primary failure.
      }
      return SettingsOperationFailure(
        code: 'reminder.persistFailed',
        userMessage: '提醒设置保存失败，已恢复原状态。请重试。（${_sanitize(error)}）',
        retryable: true,
      );
    }
    return const SettingsOperationSuccess();
  }

  static String _sanitize(Object error) {
    final text = error.toString();
    // Never surface stack traces or platform internals.
    final firstLine = text.split('\n').first;
    return firstLine.length > 80 ? '${firstLine.substring(0, 80)}…' : firstLine;
  }
}
