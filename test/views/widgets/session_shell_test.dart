// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/session_shell.dart';

/// 会话骨架（P2 组件）的行为契约：进度表达的分界、评分带回调与
/// 主操作禁用态。视觉规格由 @Preview 承担，这里只断言行为。
void main() {
  group('SessionProgressBand', () {
    testWidgets('渲染计数与退出键', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: const Scaffold(
            appBar: SessionProgressBand(currentIndex: 8, totalCount: 13),
          ),
        ),
      );
      expect(find.text('8 / 13'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('题目数超过 16 时圆点落回细进度条', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: const Scaffold(
            appBar: SessionProgressBand(currentIndex: 5, totalCount: 30),
          ),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(SessionSegmentedDots), findsNothing);
    });

    testWidgets('退出键走 onExit 回调', (tester) async {
      var exited = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Scaffold(
            appBar: SessionProgressBand(
              currentIndex: 1,
              totalCount: 3,
              onExit: () => exited = true,
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(exited, isTrue);
    });
  });

  group('SessionSegmentedDots', () {
    testWidgets('数量与 total 一致', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SessionSegmentedDots(done: 2, isCurrentReached: true, total: 5),
            ),
          ),
        ),
      );
      final dots = find.descendant(
        of: find.byType(SessionSegmentedDots),
        matching: find.byType(Container),
      );
      expect(tester.widgetList(dots).length, 5);
    });
  });

  group('SessionRatingBand', () {
    testWidgets('两档评分各回调一次，间隔小字随行', (tester) async {
      final outcomes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Scaffold(
            body: SessionRatingBand(
              above: const Text('答案 · 你好'),
              actions: [
                SessionRatingAction(
                  label: '不记得',
                  tone: SessionRatingTone.outline,
                  interval: '4 天',
                  onPressed: () => outcomes.add('no'),
                ),
                SessionRatingAction(
                  label: '记得',
                  tone: SessionRatingTone.primary,
                  interval: '9 天',
                  onPressed: () => outcomes.add('yes'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('不记得'), findsOneWidget);
      expect(find.text('记得'), findsOneWidget);
      expect(find.text('4 天'), findsOneWidget);
      expect(find.text('9 天'), findsOneWidget);

      await tester.tap(find.text('不记得'));
      await tester.tap(find.text('记得'));
      expect(outcomes, ['no', 'yes']);
    });

    testWidgets('enabled=false 时全部不可按', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Scaffold(
            body: SessionRatingBand(
              enabled: false,
              actions: [
                SessionRatingAction(
                  label: '记得',
                  tone: SessionRatingTone.primary,
                  onPressed: () => pressed = true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('记得'), warnIfMissed: false);
      expect(pressed, isFalse);
    });
  });

  group('SessionPrimaryAction', () {
    testWidgets('点击触发回调；禁用时不触发', (tester) async {
      var pressed = 0;
      Widget build({VoidCallback? onPressed}) => MaterialApp(
            theme: TurnaTheme.lightTheme,
            home: Scaffold(
              body: Center(
                child: SessionPrimaryAction(
                  label: '核对',
                  onPressed: onPressed,
                ),
              ),
            ),
          );

      await tester.pumpWidget(build(onPressed: () => pressed++));
      await tester.tap(find.text('核对'));
      expect(pressed, 1);

      await tester.pumpWidget(build());
      await tester.tap(find.text('核对'), warnIfMissed: false);
      expect(pressed, 1);
    });
  });

  group('SessionActionBand / SessionRecallCanvas', () {
    testWidgets('动作带与画布都渲染子内容', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: const Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: SessionRecallCanvas(child: Text('döner')),
                ),
                SessionActionBand(child: Text('动作带内容')),
              ],
            ),
          ),
        ),
      );
      expect(find.text('döner'), findsOneWidget);
      expect(find.text('动作带内容'), findsOneWidget);
    });
  });
}
