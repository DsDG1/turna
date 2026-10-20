// Regression guard for the "部分设置重置失败 / LateInitializationError:
// Field '_instance' has not been initialized" report.
//
// `flutter_local_notifications` declares android / iOS / macOS / Linux /
// Windows registrants only. On any other platform the platform interface's
// `_instance` is never assigned, so the very first plugin call throws
// LateInitializationError — indistinguishable from a real scheduling failure,
// and it used to abort the whole learning-settings reset.
//
// The OHOS fork is the platform that actually hits this, but it has no
// `TargetPlatform.ohos` value in the host SDK, so `fuchsia` stands in as
// "a platform the plugin does not register for": the allow-list is keyed by
// platform *name*, so the two are equivalent inputs here.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/service/local_reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalReminderService on a platform without a notification registrant',
      () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('reports that scheduling is unsupported', () {
      expect(LocalReminderService().supportsScheduling, isFalse);
    });

    test('enabling and disabling are no-ops, not LateInitializationError',
        () async {
      final service = LocalReminderService();
      await service.applyFromSettings(
        enabled: true,
        time: const TimeOfDay(hour: 9, minute: 15),
      );
      await service.applyFromSettings(
        enabled: false,
        time: const TimeOfDay(hour: 9, minute: 15),
      );
    });

    test('init and cancel are safe to call directly', () async {
      final service = LocalReminderService();
      await service.init();
      await service.cancel();
    });

    test('the test hook still runs on an unsupported platform', () async {
      final service = LocalReminderService();
      var calls = 0;
      service.testScheduleHook = (_, __) async => calls++;
      await service.applyFromSettings(
        enabled: true,
        time: const TimeOfDay(hour: 9, minute: 15),
      );
      expect(calls, 1);
    });
  });

  group('LocalReminderService on a supported platform', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('reports that scheduling is supported', () {
      expect(LocalReminderService().supportsScheduling, isTrue);
    });
  });
}
