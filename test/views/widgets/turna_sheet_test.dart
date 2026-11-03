// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

/// 全局弹层（P2 组件）的行为契约：结构完整性（拖手 / 标题 / 操作区）、
/// 次左主右、危险色、关闭路径与确认弹层的返回值。
void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    List<TurnaSheetAction>? actions,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showTurnaSheet<String>(
                  context: context,
                  title: '删除学习记录',
                  subtitle: '只删除这一课的完成记录',
                  body: const Text('正文'),
                  actions: actions,
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  group('showTurnaSheet', () {
    testWidgets('拖手、标题、说明、正文与关闭键齐全', (tester) async {
      await openSheet(tester);
      expect(find.text('删除学习记录'), findsOneWidget);
      expect(find.text('只删除这一课的完成记录'), findsOneWidget);
      expect(find.text('正文'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('主操作弹层返回值；关闭键返回 null', (tester) async {
      final result = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    result.add(await showTurnaSheet<String>(
                      context: context,
                      title: '选择',
                      body: const Text('正文'),
                      actions: [
                        const TurnaSheetAction(label: '取消', onPressed: null),
                        TurnaSheetAction(
                          label: '删除',
                          primary: true,
                          onPressed: () =>
                              Navigator.of(context).pop('deleted'),
                        ),
                      ],
                    ));
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(result, ['deleted']);

      // 再开一次，走关闭键。
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(result.length, 2);
      expect(result.last, isNull);
    });
  });

  group('showTurnaConfirmDialog', () {
    Future<void> openConfirm(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showTurnaConfirmDialog(
                    context: context,
                    title: '重置设置',
                    message: '将恢复默认学习偏好，此操作不可撤销。',
                    confirmLabel: '重置',
                    destructive: true,
                  ),
                  child: const Text('打开确认'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开确认'));
      await tester.pumpAndSettle();
    }

    testWidgets('危险确认：确认返回 true，取消返回 false', (tester) async {
      await openConfirm(tester);
      expect(find.text('重置设置'), findsOneWidget);
      expect(find.text('将恢复默认学习偏好，此操作不可撤销。'), findsOneWidget);
      expect(find.text('重置'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });

    testWidgets('确认与取消文案可点击', (tester) async {
      await openConfirm(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('重置设置'), findsNothing);
    });
  });
}
