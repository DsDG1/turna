// Widget tests for SystemHealthPage (state-machine version, Plan §15).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/system_health_monitor.dart';
import 'package:turna/core/log_capture.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/settings/system_health_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late SystemHealthMonitor monitor;
  late ValueNotifier<List<LogEntry>> logs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    await sp.setString(LocalStateKeys.systemHealthEvent, '');
    prefs = AppPrefs(sp);
    logs = ValueNotifier<List<LogEntry>>([]);
    monitor = SystemHealthMonitor(prefs, integrityProbe: () async => 'ok');
    await monitor.install(logs);

    if (getIt.isRegistered<AppPrefs>()) {
      await getIt.reset();
    }
    getIt.registerSingleton<AppPrefs>(prefs);
  });

  tearDown(() async {
    await getIt.reset();
  });

  Widget wrap(Widget child) {
    return ChangeNotifierProvider<SystemHealthMonitor>.value(
      value: monitor,
      child: ChangeNotifierProvider<SettingsProvider>.value(
        value: SettingsProvider(prefs),
        child: MaterialApp(home: child),
      ),
    );
  }

  testWidgets('SystemHealthPage renders header, summary, and action items',
      (tester) async {
    await tester.pumpWidget(wrap(const SystemHealthPage()));
    await tester.pumpAndSettle();

    expect(find.text('系统健康'), findsOneWidget);
    expect(find.text('主要问题'), findsOneWidget);
    expect(find.text('处理操作'), findsOneWidget);
    expect(find.text('查看诊断建议'), findsOneWidget);
    expect(find.text('运行自检'), findsOneWidget);
  });

  testWidgets('Safe mode toggle updates monitor', (tester) async {
    await tester.pumpWidget(wrap(const SystemHealthPage()));
    await tester.pumpAndSettle();

    expect(monitor.safeMode, isFalse);
    final safeModeTile = find.text('安全模式');
    await tester.scrollUntilVisible(
      safeModeTile,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(monitor.safeMode, isTrue);
  });

  testWidgets(
      'critical alert shows a NON-blocking banner; no score-deduction UI exists',
      (tester) async {
    // 15 distinct error groups -> 45 points -> critical level.
    final now = DateTime.now();
    logs.value = [
      for (var i = 0; i < 15; i++)
        LogEntry(
          timestamp: now.add(Duration(milliseconds: i)),
          level: Level.error,
          message: 'error-$i',
        ),
    ];
    await tester.pump(const Duration(milliseconds: 50));
    expect(monitor.score, 45);
    expect(monitor.level, SystemHealthLevel.critical);

    await tester.pumpWidget(wrap(const SystemHealthPage()));
    await tester.pumpAndSettle();

    // Non-blocking banner explains the state…
    expect(find.textContaining('检测到异常'), findsOneWidget);
    // …the manual score deduction is gone everywhere…
    expect(find.textContaining('确定（-40分）'), findsNothing);
    expect(find.textContaining('降低40分'), findsNothing);
    // …and the page never blocks pop: there is no PopScope at all.
    expect(find.byType(PopScope), findsNothing);
  });

  testWidgets('acknowledge hides the banner without touching the facts',
      (tester) async {
    final now = DateTime.now();
    logs.value = [
      for (var i = 0; i < 15; i++)
        LogEntry(
          timestamp: now.add(Duration(milliseconds: i)),
          level: Level.error,
          message: 'error-$i',
        ),
    ];
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(wrap(const SystemHealthPage()));
    await tester.pumpAndSettle();

    final acknowledge = find.text('我知道了');
    await tester.scrollUntilVisible(
      acknowledge,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(acknowledge);
    await tester.pumpAndSettle();

    expect(monitor.acknowledged, isTrue);
    expect(find.textContaining('检测到异常'), findsNothing);
    // Facts unchanged.
    expect(monitor.score, 45);
    expect(monitor.resolved, isFalse);
  });
}
