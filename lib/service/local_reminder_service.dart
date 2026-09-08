// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/language_provider.dart';
import 'package:turna/di/injection.dart';

/// Schedules a gentle daily review reminder (no streak pressure).
@lazySingleton
class LocalReminderService {
  LocalReminderService();

  static const int notificationId = 2201;
  static const String channelId = 'turna_daily_review';
  static const String channelName = 'Daily review';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Notification copy snapshots the learner's current language at schedule
  /// time — the notification itself fires later, without process context.
  String _reminderBody() {
    if (getIt.isRegistered<LanguageProvider>()) {
      final name = getIt<LanguageProvider>().displayName;
      return 'Time for a quick $name review';
    }
    return 'Time for a quick review';
  }

  String _channelDescription() {
    if (getIt.isRegistered<LanguageProvider>()) {
      return 'Gentle daily reminder to review '
          '${getIt<LanguageProvider>().displayName}';
    }
    return 'Gentle daily reminder';
  }

  /// Optional override for unit tests (no platform channels).
  @visibleForTesting
  Future<void> Function(bool enabled, TimeOfDay time)? testScheduleHook;

  Future<void> init() async {
    if (kIsWeb) return;
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/launcher_icon');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(
        android: android,
        iOS: ios,
      ),
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> applyFromSettings({
    required bool enabled,
    required TimeOfDay time,
  }) async {
    final hook = testScheduleHook;
    if (hook != null) {
      await hook(enabled, time);
      return;
    }
    if (kIsWeb) return;
    await init();
    if (!enabled) {
      await cancel();
      return;
    }
    await scheduleDaily(time);
  }

  Future<void> scheduleDaily(TimeOfDay time) async {
    if (kIsWeb) return;
    await init();

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: _channelDescription(),
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );

    // periodicallyShow approximates a daily cadence without the timezone
    // package. Scheduling failures PROPAGATE: UpdateDailyReminderCommand must
    // know the OS refused the schedule so it never commits the preference.
    await _plugin.periodicallyShow(
      notificationId,
      'Turna',
      _reminderBody(),
      RepeatInterval.daily,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancel() async {
    if (kIsWeb) return;
    await _plugin.cancel(notificationId);
  }
}
