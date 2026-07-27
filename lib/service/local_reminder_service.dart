// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';

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

    const android = AndroidInitializationSettings('@mipmap/launcher_icon');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
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

    // Use periodicallyShow as a workaround since timezone package
    // is not compatible with Dart 3.6.2 (Flutter-OH).
    // This shows a daily notification at approximately 24-hour intervals.
    try {
      await _plugin.periodicallyShow(
        notificationId,
        'Varnamala',
        reminderBody,
        RepeatInterval.daily,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('LocalReminderService schedule failed: $e');
    }
  }

  Future<void> cancel() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(notificationId);
    } catch (e) {
      debugPrint('LocalReminderService cancel failed: $e');
    }
  }
}
