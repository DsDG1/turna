// Unit tests for the system-health state machine (Plan §15):
// detected / acknowledged / mitigation / checkPassed / resolved / expired
// are separate concepts; no manual score deduction exists; resolution only
// comes from system evidence.

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/system_health_monitor.dart';
import 'package:turna/core/log_capture.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences sp;
  late AppPrefs prefs;
  late ValueNotifier<List<LogEntry>> logs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sp = await StreamingSharedPreferences.instance;
    await sp.setString(LocalStateKeys.systemHealthEvent, '');
    prefs = AppPrefs(sp);
    logs = ValueNotifier<List<LogEntry>>([]);
  });

  SystemHealthMonitor installMonitor({
    Future<String> Function()? integrityProbe,
  }) {
    return SystemHealthMonitor(prefs, integrityProbe: integrityProbe);
  }

  LogEntry errorEntry(String message, {DateTime? at}) => LogEntry(
        timestamp: at ?? DateTime.now(),
        level: Level.error,
        message: message,
      );

  test('starts normal with no logs', () async {
    final monitor = installMonitor();
    await monitor.install(logs);
    expect(monitor.level, SystemHealthLevel.normal);
    expect(monitor.score, 0);
    expect(monitor.resolved, isFalse); // no self-check ran yet
    expect(monitor.hasUnacknowledgedAlert, isFalse);
    expect(monitor.hasDataIntegrityBlock, isFalse);
  });

  test('distinct error groups aggregate into attention', () async {
    final monitor = installMonitor();
    await monitor.install(logs);

    final now = DateTime.now();
    logs.value = [
      for (var i = 0; i < 4; i++)
        errorEntry('distinct-error-$i', at: now.add(Duration(seconds: i))),
    ];
    await Future<void>.delayed(Duration.zero);

    // 4 distinct fingerprints x 3 points = 12 -> attention, unacknowledged.
    expect(monitor.score, 12);
    expect(monitor.level, SystemHealthLevel.attention);
    expect(monitor.hasUnacknowledgedAlert, isTrue);
  });

  test('a fatal group pins the level at critical', () async {
    final monitor = installMonitor();
    await monitor.install(logs);

    logs.value = [
      LogEntry(
        timestamp: DateTime.now(),
        level: Level.fatal,
        message: 'fatal-boom',
      ),
    ];
    await Future<void>.delayed(Duration.zero);

    expect(monitor.score, SystemHealthMonitor.alertThreshold);
    expect(monitor.level, SystemHealthLevel.critical);
  });

  test('acknowledge hides the alert but never fakes resolution', () async {
    final monitor = installMonitor();
    await monitor.install(logs);

    final now = DateTime.now();
    logs.value = [
      for (var i = 0; i < 15; i++)
        errorEntry('ack-error-$i', at: now.add(Duration(seconds: i))),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(monitor.hasUnacknowledgedAlert, isTrue);

    await monitor.acknowledge();
    expect(monitor.hasUnacknowledgedAlert, isFalse);
    expect(monitor.acknowledged, isTrue);
    // Acknowledging changed NOTHING about the facts:
    expect(monitor.score, 45);
    expect(monitor.level, SystemHealthLevel.critical);
    expect(monitor.resolved, isFalse);
  });

  test('self-check does not resolve while the score is still high', () async {
    final monitor = installMonitor(integrityProbe: () async => 'ok');
    await monitor.install(logs);

    final now = DateTime.now();
    logs.value = [
      for (var i = 0; i < 15; i++)
        errorEntry('resolve-error-$i', at: now.add(Duration(seconds: i))),
    ];
    await Future<void>.delayed(Duration.zero);

    final passed = await monitor.runSelfCheck();
    expect(passed, isFalse);
    expect(monitor.resolved, isFalse);
  });

  test('self-check resolves a decayed event and clears the integrity flag',
      () async {
    final monitor = installMonitor(integrityProbe: () async => 'ok');
    await monitor.install(logs);

    // No active groups: an acknowledged old event with a passing probe.
    await monitor.reportDataIntegrityRisk('probe says suspicious');
    expect(monitor.hasDataIntegrityBlock, isTrue);

    final passed = await monitor.runSelfCheck();
    expect(passed, isTrue);
    expect(monitor.resolved, isTrue);
    expect(monitor.hasDataIntegrityBlock, isFalse,
        reason: 'passing integrity clears the hazard flag');
  });

  test('integrity failure keeps the event unresolved', () async {
    final monitor = installMonitor(integrityProbe: () async => 'corrupt page');
    await monitor.install(logs);
    final passed = await monitor.runSelfCheck();
    expect(passed, isFalse);
    expect(monitor.resolved, isFalse);
  });

  test('a new detection invalidates prior check evidence and reopens the alert',
      () async {
    final monitor = installMonitor(integrityProbe: () async => 'ok');
    await monitor.install(logs);

    await monitor.acknowledge();
    await monitor.runSelfCheck();
    expect(monitor.resolved, isTrue);

    logs.value = [
      LogEntry(
        timestamp: DateTime.now().add(const Duration(minutes: 1)),
        level: Level.error,
        message: 'fresh-error',
      ),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(monitor.acknowledged, isFalse,
        reason: 'new detection reopens the alert');
  });

  test('score decays as groups age out of the active window', () async {
    final old = DateTime.now()
        .subtract(const Duration(hours: 25))
        .millisecondsSinceEpoch;
    await prefs.preferences.setString(
      LocalStateKeys.systemHealthEvent,
      '{"id":"health-old","firstAt":$old,"lastAt":$old,'
      '"lastProcessedAt":$old,"groups":{'
      '"f1":{"fingerprint":"f1","level":"error","message":"old",'
      '"module":"x","count":9,"firstAt":$old,"lastAt":$old,'
      '"lastScoredAt":$old}},'
      '"dialogShown":true,"acknowledged":true,"safeMode":false,'
      '"checkPassed":false,"dataIntegrityBlock":false,'
      '"dataIntegrityReason":"","appVersion":"unknown"}',
    );
    final reloaded = SystemHealthMonitor(prefs);
    await reloaded.install(logs);
    expect(reloaded.score, 0);
    expect(reloaded.level, SystemHealthLevel.normal);
  });

  test('data-integrity hazard is a dedicated flag, independent of scores',
      () async {
    final monitor = installMonitor();
    await monitor.install(logs);

    expect(monitor.hasDataIntegrityBlock, isFalse);
    await monitor.reportDataIntegrityRisk('deck media mismatch /db/x');
    expect(monitor.hasDataIntegrityBlock, isTrue);
    expect(monitor.dataIntegrityReason, contains('deck media mismatch'));
    // No log entries were needed and the log score is untouched.
    expect(monitor.score, 0);
  });

  test('legacy `handled` events load as acknowledged', () async {
    await prefs.preferences.setString(
      LocalStateKeys.systemHealthEvent,
      '{"id":"health-legacy","firstAt":1,"lastAt":1,"lastProcessedAt":1,'
      '"groups":{},"dialogShown":true,"acknowledged":false,'
      '"handled":true,"safeMode":false,"appVersion":"unknown"}',
    );
    final monitor = SystemHealthMonitor(prefs);
    await monitor.install(logs);
    expect(monitor.acknowledged, isTrue);
  });

  test('safe mode is a runtime overlay flag', () async {
    final monitor = installMonitor();
    await monitor.install(logs);
    expect(monitor.safeMode, isFalse);
    await monitor.setSafeMode(true);
    expect(monitor.safeMode, isTrue);
    await monitor.setSafeMode(false);
    expect(monitor.safeMode, isFalse);
  });
}
