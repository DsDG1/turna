// Widget tests for SystemHealthPage

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
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
    monitor = SystemHealthMonitor(prefs);
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
      child: MaterialApp(home: child),
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

  testWidgets('Score >= 40 shows banner and confirm deduction button',
      (tester) async {
    // Generate enough errors to exceed 40 points
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
    expect(monitor.isScoreExceeded, isTrue);

    await tester.pumpWidget(wrap(const SystemHealthPage()));
    await tester.pumpAndSettle();

    // Banner and action button are shown
    expect(find.textContaining('已达到或超过 40 分阈值'), findsOneWidget);
    expect(find.text('确定（-40分）'), findsOneWidget);

    // Tap confirm button
    await tester.tap(find.text('确定（-40分）'));
    await tester.pumpAndSettle();

    // Confirm dialog is presented
    expect(find.text('确认处理异常并降低 40 分？'), findsOneWidget);
    expect(find.textContaining('当前异常评分：45 分'), findsOneWidget);
    expect(find.textContaining('处理后评分：5 分'), findsOneWidget);

    // Tap confirm inside dialog
    await tester.tap(find.widgetWithText(TextButton, '确定（-40分）').last);
    await tester.pumpAndSettle();

    // Score is now 5 (< 40)
    expect(monitor.score, 5);
    expect(monitor.isScoreExceeded, isFalse);
  });
}
