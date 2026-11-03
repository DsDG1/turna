// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/directory_rows.dart';

/// 目录行族（P2 组件）的行为契约：状态形状、锁定不可点、值行的
/// control 优先权。行高与字号规格由 @Preview 承担。
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: Scaffold(body: child),
      );

  group('DirectoryLessonRow', () {
    testWidgets('完成行画勾、当前行画环（无勾）', (tester) async {
      await tester.pumpWidget(
        wrap(const Column(
          children: [
            DirectoryLessonRow(
              status: DirectoryNodeStatus.done,
              title: '已完成课时',
            ),
            DirectoryLessonRow(
              status: DirectoryNodeStatus.current,
              title: '当前课时',
            ),
          ],
        )),
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.text('已完成课时'), findsOneWidget);
      expect(find.text('当前课时'), findsOneWidget);
    });

    testWidgets('可点行触发回调；锁定行不触发', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(Column(
          children: [
            DirectoryLessonRow(
              status: DirectoryNodeStatus.todo,
              title: '未学课时',
              onTap: () => taps++,
            ),
            const DirectoryLessonRow(
              status: DirectoryNodeStatus.locked,
              title: '锁定课时',
              // 锁定行即使误传 onTap 也不可点（onTap 缺省即 null）。
            ),
          ],
        )),
      );
      await tester.tap(find.text('未学课时'));
      expect(taps, 1);
      await tester.tap(find.text('锁定课时'), warnIfMissed: false);
      expect(taps, 1);
    });
  });

  group('DirectorySubLessonRow', () {
    testWidgets('当前行渲染且可点', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(DirectorySubLessonRow(
          status: DirectoryNodeStatus.current,
          title: '欢迎来到土耳其语的世界',
          onTap: () => tapped = true,
        )),
      );
      await tester.tap(find.text('欢迎来到土耳其语的世界'));
      expect(tapped, isTrue);
    });
  });

  group('DirectoryTaskRow', () {
    testWidgets('计数与 chevron 渲染，点击触发', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(DirectoryTaskRow(
          icon: Icons.book_rounded,
          accent: TurnaTheme.brandTeal,
          title: '单词 · SRS',
          countLabel: '12',
          onTap: () => tapped = true,
        )),
      );
      expect(find.text('12'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('单词 · SRS'));
      expect(tapped, isTrue);
    });
  });

  group('DirectoryEntryRow', () {
    testWidgets('标题、释义与元信息齐全', (tester) async {
      await tester.pumpWidget(
        wrap(const DirectoryEntryRow(
          title: 'merhaba',
          subtitle: '感叹词 · 你好',
          meta: 'Türkçe 1k · 已学',
        )),
      );
      expect(find.text('merhaba'), findsOneWidget);
      expect(find.text('感叹词 · 你好'), findsOneWidget);
      expect(find.text('Türkçe 1k · 已学'), findsOneWidget);
    });
  });

  group('DirectoryLinkRow', () {
    testWidgets('图标井 + 说明 + chevron', (tester) async {
      await tester.pumpWidget(
        wrap(const DirectoryLinkRow(
          icon: Icons.book_rounded,
          iconTone: TurnaTheme.brandTeal,
          title: '学习',
          description: '语言、课程更新、朗读与复习节奏',
        )),
      );
      expect(find.byIcon(Icons.book_rounded), findsOneWidget);
      expect(find.text('语言、课程更新、朗读与复习节奏'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });
  });

  group('DirectoryValueRow', () {
    testWidgets('值右对齐渲染，可点行带 chevron', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(DirectoryValueRow(
          label: '主题',
          value: '跟随系统',
          onTap: () => tapped = true,
        )),
      );
      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('主题'));
      expect(tapped, isTrue);
    });

    testWidgets('给了 control 就不画值与 chevron，行不抢点按', (tester) async {
      var rowTaps = 0;
      var switchToggles = 0;
      await tester.pumpWidget(
        wrap(StatefulBuilder(
          builder: (context, setState) => DirectoryValueRow(
            label: '自动播放发音',
            control: Switch(
              value: false,
              onChanged: (_) {
                setState(() {});
                switchToggles++;
              },
            ),
            onTap: () => rowTaps++,
          ),
        )),
      );
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      await tester.tap(find.byType(Switch));
      expect(switchToggles, 1);
      expect(rowTaps, 0, reason: '控件行的事件归控件，不冒泡成行点按');
    });
  });

  group('DirectoryGroupHeader', () {
    testWidgets('序号块与计数渲染，点击触发', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(DirectoryGroupHeader(
          indexLabel: '5',
          title: '咖啡与茶',
          meta: '0 / 4',
          onTap: () => tapped = true,
        )),
      );
      expect(find.text('5'), findsOneWidget);
      expect(find.text('0 / 4'), findsOneWidget);
      await tester.tap(find.text('咖啡与茶'));
      expect(tapped, isTrue);
    });
  });
}
