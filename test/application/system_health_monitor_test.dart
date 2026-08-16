import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/system_health_monitor.dart';
import 'package:turna/core/log_capture.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ValueNotifier<List<LogEntry>> logs;
  late SystemHealthMonitor monitor;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final streaming = await StreamingSharedPreferences.instance;
    await streaming.setString(LocalStateKeys.systemHealthEvent, '');
    logs = ValueNotifier<List<LogEntry>>([]);
    monitor = SystemHealthMonitor(AppPrefs(streaming));
    await monitor.install(logs);
  });

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  test('fatal enters critical state immediately', () async {
    logs.value = [
      LogEntry(
        timestamp: DateTime.now(),
        level: Level.fatal,
        message: 'database unavailable',
      ),
    ];
    await settle();
    expect(monitor.level, SystemHealthLevel.critical);
    expect(monitor.score, greaterThanOrEqualTo(30));
    expect(monitor.shouldShowCriticalDialog, isTrue);
  });

  test('30 identical loop errors form one group and one score bucket',
      () async {
    final start = DateTime.now();
    logs.value = [
      for (var i = 0; i < 30; i++)
        LogEntry(
          timestamp: start.add(Duration(milliseconds: i)),
          level: Level.error,
          message: 'WebView failed id=${10000 + i}',
        ),
    ];
    await settle();
    expect(monitor.event.groups, hasLength(1));
    expect(monitor.event.groups.values.single.count, 30);
    expect(monitor.score, 3);
  });

  test('warning score reaches attention at ten distinct groups', () async {
    final start = DateTime.now();
    logs.value = [
      for (var i = 0; i < 10; i++)
        LogEntry(
          timestamp: start.add(Duration(milliseconds: i)),
          level: Level.warning,
          message: 'module-${String.fromCharCode(65 + i)} failed',
        ),
    ];
    await settle();
    expect(monitor.score, 10);
    expect(monitor.level, SystemHealthLevel.attention);
  });

  test('mark handled keeps history but new error creates new event', () async {
    final first = DateTime.now();
    logs.value = [
      LogEntry(timestamp: first, level: Level.fatal, message: 'fatal one'),
    ];
    await settle();
    final oldId = monitor.event.id;
    await monitor.markHandled();

    logs.value = [
      LogEntry(
        timestamp: first.add(const Duration(seconds: 1)),
        level: Level.warning,
        message: 'new warning',
      ),
      ...logs.value,
    ];
    await settle();
    expect(monitor.event.id, isNot(oldId));
    expect(monitor.event.handled, isFalse);
    expect(monitor.score, 1);
  });

  test('safe mode exits without mutating event history', () async {
    await monitor.setSafeMode(true);
    expect(monitor.safeMode, isTrue);
    await monitor.setSafeMode(false);
    expect(monitor.safeMode, isFalse);
    expect(monitor.event.groups, isEmpty);
  });

  test('critical event persists across restart without repeating dialog',
      () async {
    final fatal = LogEntry(
      timestamp: DateTime.now(),
      level: Level.fatal,
      message: 'persistent fatal',
    );
    logs.value = [fatal];
    await settle();
    await monitor.markDialogShown();

    final streaming = await StreamingSharedPreferences.instance;
    final restarted = SystemHealthMonitor(AppPrefs(streaming));
    final restoredLogs = ValueNotifier<List<LogEntry>>([fatal]);
    await restarted.install(restoredLogs);

    expect(restarted.level, SystemHealthLevel.critical);
    expect(restarted.score, monitor.score);
    expect(restarted.shouldShowCriticalDialog, isFalse);
  });

  test('clearing the log source does not claim the incident is resolved',
      () async {
    logs.value = [
      LogEntry(
        timestamp: DateTime.now(),
        level: Level.fatal,
        message: 'fatal before clear',
      ),
    ];
    await settle();
    logs.value = const [];
    await settle();
    expect(monitor.level, SystemHealthLevel.critical);
    expect(monitor.event.handled, isFalse);
  });

  test('score reaches 40 triggers shouldForceRedirect and reduces 40 on confirm',
      () async {
    final start = DateTime.now();
    // 14 distinct errors = 14 * 3 = 42 points (> 40)
    logs.value = [
      for (var i = 0; i < 14; i++)
        LogEntry(
          timestamp: start.add(Duration(milliseconds: i)),
          level: Level.error,
          message: 'error-$i occurred',
        ),
    ];
    await settle();
    expect(monitor.score, 42);
    expect(monitor.isScoreExceeded, isTrue);
    expect(monitor.shouldForceRedirect, isTrue);

    // Confirm and deduct 40
    await monitor.confirmAndDeductScore(40);
    expect(monitor.score, 2); // 42 - 40 = 2 (not below 0)
    expect(monitor.isScoreExceeded, isFalse);
    expect(monitor.shouldForceRedirect, isFalse);
    expect(monitor.event.handled, isTrue);

    // New errors accumulate from 2 points
    // 13 more errors = 13 * 3 = 39 points; 2 + 39 = 41 (> 40)
    logs.value = [
      ...logs.value,
      for (var i = 14; i < 27; i++)
        LogEntry(
          timestamp: start.add(Duration(seconds: 10 + i)),
          level: Level.error,
          message: 'error-$i occurred',
        ),
    ];
    await settle();
    expect(monitor.score, 41);
    expect(monitor.isScoreExceeded, isTrue);
    expect(monitor.shouldForceRedirect, isTrue);

    // Confirm again to deduct 40: 41 - 40 = 1
    await monitor.confirmAndDeductScore(40);
    expect(monitor.score, 1);
    expect(monitor.isScoreExceeded, isFalse);
    expect(monitor.shouldForceRedirect, isFalse);

    // If score is 1 and deduct 40 -> drops to 0, not below 0
    await monitor.confirmAndDeductScore(40);
    expect(monitor.score, 0);
  });
}
