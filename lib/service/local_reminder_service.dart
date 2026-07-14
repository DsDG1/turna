// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Schedules a gentle daily review reminder (no streak pressure).
@lazySingleton
class LocalReminderService {
  LocalReminderService();

  static const int notificationId = 2201;
  static const String channelId = 'varnamala_daily_review';
  static const String channelName = 'Daily review';
  static const String reminderBody = 'Time for a quick Turkish review';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Optional override for unit tests (no platform channels).
  @visibleForTesting
  Future<void> Function(bool enabled, TimeOfDay time)? testScheduleHook;

  Future<void> init() async {
    if (kIsWeb) return;
    if (_initialized) return;

    tz_data.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/launcher_icon');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
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

    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Gentle daily reminder to review Turkish',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    final scheduled = _nextInstanceOfTime(time);

    try {
      await _plugin.zonedSchedule(
        id: notificationId,
        title: 'Varnamala',
        body: reminderBody,
        scheduledDate: scheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('LocalReminderService schedule failed: $e');
    }
  }

  Future<void> cancel() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(id: notificationId);
    } catch (e) {
      debugPrint('LocalReminderService cancel failed: $e');
    }
  }

  tz.TZDateTime _nextInstanceOfTime(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
