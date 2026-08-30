// Consolidated unit tests for SettingsProvider (learning, reminders, per-course, and Anki settings).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/service/local_reminder_service.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final streaming = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(streaming);
    settings = SettingsProvider(prefs);
  });

  group('Daily reminder and learning defaults', () {
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

    test('resetLearningDefaults restores TTS, reminder, and retention', () async {
      await settings.setTtsSpeed(1.5);
      await settings.setDailyReminderEnabled(true);
      await settings.setDailyReminderTime(const TimeOfDay(hour: 8, minute: 15));
      await settings.setSrsDesiredRetention(0.85);

      await settings.resetLearningDefaults();

      expect(settings.ttsSpeed, 1.0);
      expect(settings.dailyReminderEnabled, isFalse);
      expect(settings.dailyReminderHour, 19);
      expect(settings.dailyReminderMinute, 0);
      expect(settings.srsDesiredRetention, 0.9);

      final reloaded = SettingsProvider(prefs);
      expect(reloaded.ttsSpeed, 1.0);
      expect(reloaded.dailyReminderEnabled, isFalse);
      expect(reloaded.dailyReminderHour, 19);
    });

    test('setTtsSpeed clamps to 0.5–2.0 and persists', () async {
      await settings.setTtsSpeed(3.0);
      expect(settings.ttsSpeed, 2.0);
      await settings.setTtsSpeed(0.1);
      expect(settings.ttsSpeed, 0.5);

      final reloaded = SettingsProvider(prefs);
      expect(reloaded.ttsSpeed, 0.5);
    });
  });

  group('Per-course settings', () {
    test('auto-read-on-tap defaults to true for any scope', () {
      expect(settings.autoReadOnTapFor(''), isTrue);
      expect(settings.autoReadOnTapFor('anki:abc123'), isTrue);
    });

    test('auto-read-on-tap set + persist, isolated per scope', () async {
      await settings.setAutoReadOnTapFor('', false);
      await settings.setAutoReadOnTapFor('anki:abc123', false);
      await settings.setAutoReadOnTapFor('anki:def456', true);

      final reloaded = SettingsProvider(prefs);
      expect(reloaded.autoReadOnTapFor(''), isFalse);
      expect(reloaded.autoReadOnTapFor('anki:abc123'), isFalse);
      expect(reloaded.autoReadOnTapFor('anki:def456'), isTrue);
      expect(reloaded.autoReadOnTapFor('anki:untouched'), isTrue);
    });

    test('auto-read-on-tap uses distinct pref keys per scope', () async {
      await settings.setAutoReadOnTapFor('anki:abc123', false);
      expect(settings.autoReadOnTapFor('anki:def456'), isTrue);
    });

    test('native language defaults to en for any scope', () {
      expect(settings.nativeLanguageCodeFor(''), 'en');
      expect(settings.nativeLanguageCodeFor('anki:abc123'), 'en');
    });

    test('native language set + persist, isolated per scope', () async {
      await settings.setNativeLanguageCodeFor('', 'zh');
      await settings.setNativeLanguageCodeFor('anki:abc123', 'ru');

      final reloaded = SettingsProvider(prefs);
      expect(reloaded.nativeLanguageCodeFor(''), 'zh');
      expect(reloaded.nativeLanguageCodeFor('anki:abc123'), 'ru');
      expect(reloaded.nativeLanguageCodeFor('anki:untouched'), 'en');
    });
  });

  group('Anki engine settings', () {
    test('defaults and setters persist for force-disable JS', () async {
      expect(settings.ankiForceDisableJs, isFalse);

      await settings.setAnkiForceDisableJs(true);

      final reloaded = SettingsProvider(prefs);
      expect(reloaded.ankiForceDisableJs, isTrue);
    });
  });
}
