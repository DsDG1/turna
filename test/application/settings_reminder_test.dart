import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/service/local_reminder_service.dart';
import 'package:varnamala/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    settings = SettingsProvider(prefs);
  });

  test('daily reminder prefs default off at 19:00', () {
    expect(settings.dailyReminderEnabled, isFalse);
    expect(settings.dailyReminderHour, 19);
    expect(settings.dailyReminderMinute, 0);
  });

  test('setDailyReminderEnabled and time persist', () async {
    await settings.setDailyReminderEnabled(true);
    await settings.setDailyReminderTime(const TimeOfDay(hour: 8, minute: 30));

    final reloaded = SettingsProvider(prefs);
    expect(reloaded.dailyReminderEnabled, isTrue);
    expect(reloaded.dailyReminderHour, 8);
    expect(reloaded.dailyReminderMinute, 30);
  });

  test('LocalReminderService test hook is invoked', () async {
    final service = LocalReminderService();
    bool? seenEnabled;
    TimeOfDay? seenTime;
    service.testScheduleHook = (enabled, time) async {
      seenEnabled = enabled;
      seenTime = time;
    };

    await service.applyFromSettings(
      enabled: true,
      time: const TimeOfDay(hour: 9, minute: 15),
    );

    expect(seenEnabled, isTrue);
    expect(seenTime, const TimeOfDay(hour: 9, minute: 15));
  });
}
