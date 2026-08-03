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
  static const String channelId = 'turna_daily_review';
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
    // HarmonyOS: the OHos plugin branch (defaultTargetPlatform == ohos)
    // requires an OhosInitializationSettings; without it `initialize` throws
    // "Ohos settings must be set". The defaultIcon name resolves against the
    // OHos resources media/ folder (we ship launcher_icon.png there).
    const ohos = OhosInitializationSettings('@mipmap/launcher_icon');
    await _plugin.initialize(
      const InitializationSettings(
        android: android,
        iOS: ios,
        ohos: ohos,
      ),
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    // HarmonyOS: enable notifications via notificationManager — a prerequisite
    // for periodicallyShow (which maps to reminderAgentManager) to actually
    // fire. No-op on Android/iOS (the resolved plugin is null there).
    final ohosPlugin = _plugin.resolvePlatformSpecificImplementation<
        OhosFlutterLocalNotificationsPlugin>();
    await ohosPlugin?.requestNotificationsPermission();

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
    // HarmonyOS: a SERVICE_INFORMATION slot is the appropriate type for a
    // daily review reminder. The base periodicallyShow routes by platform;
    // on Android/iOS the `ohos:` field is ignored.
    const ohosDetails = OhosNotificationDetails(
      OhosNotificationSlotType.SERVICE_INFORMATION,
      slotDesc: 'Gentle daily reminder to review Turkish',
      importance: OhosImportance.defaultImportance,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
      ohos: ohosDetails,
    );

    // Use periodicallyShow as a workaround since timezone package
    // is not compatible with Dart 3.6.2 (Flutter-OH).
    // This shows a daily notification at approximately 24-hour intervals.
    try {
      await _plugin.periodicallyShow(
        notificationId,
        'Turna',
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
