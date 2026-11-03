// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/search_field.dart';

/// 搜索基元（P2 组件）的行为契约：防抖只给终值、清除立即回调、
/// 查询中尾标切换。
void main() {
  Widget wrap({required Widget child}) => MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('停顿后只回调一次终值', (tester) async {
    final delivered = <String>[];
    await tester.pumpWidget(wrap(
      child: TurnaSearchField(
        hint: '搜索',
        onDebouncedChanged: delivered.add,
      ),
    ));

    await tester.enterText(find.byType(TextField), 'mer');
    await tester.pump(const Duration(milliseconds: 100));
    expect(delivered, isEmpty, reason: '防抖窗口内不应回调');

    await tester.pump(const Duration(milliseconds: 250));
    expect(delivered, ['mer']);
  });

  testWidgets('连续输入只投递最后一次', (tester) async {
    final delivered = <String>[];
    await tester.pumpWidget(wrap(
      child: TurnaSearchField(
        hint: '搜索',
        onDebouncedChanged: delivered.add,
      ),
    ));

    await tester.enterText(find.byType(TextField), 'm');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.enterText(find.byType(TextField), 'me');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.enterText(find.byType(TextField), 'mer');
    await tester.pump(const Duration(milliseconds: 300));

    expect(delivered, ['mer']);
  });

  testWidgets('清除键立即回调空串，不等防抖', (tester) async {
    final delivered = <String>[];
    await tester.pumpWidget(wrap(
      child: TurnaSearchField(
        hint: '搜索',
        onDebouncedChanged: delivered.add,
      ),
    ));

    await tester.enterText(find.byType(TextField), 'merhaba');
    await tester.pump(const Duration(milliseconds: 300));
    expect(delivered, ['merhaba']);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(delivered, ['merhaba', '']);
  });

  testWidgets('searching 时尾部是 spinner，清除键暂避', (tester) async {
    await tester.pumpWidget(wrap(
      child: TurnaSearchField(
        hint: '搜索',
        onDebouncedChanged: (_) {},
        searching: true,
      ),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('外部 controller 变更时自管 controller 不泄漏覆盖', (tester) async {
    final external = TextEditingController(text: '');
    await tester.pumpWidget(wrap(
      child: TurnaSearchField(
        controller: external,
        onDebouncedChanged: (_) {},
      ),
    ));
    await tester.enterText(find.byType(TextField), 'ev');
    expect(external.text, 'ev');
  });
}
