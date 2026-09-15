// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:injectable/injectable.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

// Project imports:
import 'package:turna/application/language_provider.dart';
import 'package:turna/core/logger.dart';
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
  bool _tzReady = false;

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

    // zonedSchedule + DateTimeComponents.time repeats daily at the chosen
    // wall-clock time — periodicallyShow would ignore [time] and simply
    // fire every 24h from whenever the schedule happened to run.
    // Scheduling failures PROPAGATE: UpdateDailyReminderCommand must
    // know the OS refused the schedule so it never commits the preference.
    await _ensureTimezones();
    await _plugin.zonedSchedule(
      notificationId,
      'Turna',
      _reminderBody(),
      _nextInstanceOf(time),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// First upcoming occurrence of [time] in the device's local zone.
  tz.TZDateTime _nextInstanceOf(TimeOfDay time) {
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

  /// Loads the tz database and binds [tz.local] to the device's IANA zone
  /// (idempotent). Without this, [tz.local] stays UTC and the reminder would
  /// fire at the right clock time in the wrong zone.
  Future<void> _ensureTimezones() async {
    if (_tzReady) return;
    _tzReady = true;
    tz_data.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // No IANA name available (headless test host): fall back to the first
      // zone whose current UTC offset equals the device's. Zones sharing an
      // offset can differ on DST, but this beats scheduling in UTC.
      final offset = DateTime.now().timeZoneOffset.inMilliseconds;
      for (final name in tz.timeZoneDatabase.locations.keys) {
        final loc = tz.getLocation(name);
        if (loc.currentTimeZone.offset == offset) {
          tz.setLocalLocation(loc);
          break;
        }
      }
      logger.w(
        'LocalReminderService: IANA timezone lookup failed ($e); '
        'matched by UTC offset instead',
      );
    }
  }

  Future<void> cancel() async {
    if (kIsWeb) return;
    await _plugin.cancel(notificationId);
  }
}
