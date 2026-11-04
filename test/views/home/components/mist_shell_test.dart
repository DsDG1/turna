// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/views/home/components/light_top_bar.dart';
import 'package:turna/views/home/components/text_tab_bar.dart';

/// 外壳两件（P2 组件）的行为契约：顶栏只承载课程切换与连胜，
/// 文字导航的选中语义与受光短条占位。
void main() {
  group('LightTopBar', () {
    testWidgets('课程名与连胜渲染，切换可点', (tester) async {
      var switched = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Scaffold(
            appBar: LightTopBar(
              courseName: '土耳其语 · 新版',
              onSwitchCourse: () => switched = true,
              streakLabel: '7 天',
            ),
          ),
        ),
      );
      expect(find.text('土耳其语 · 新版'), findsOneWidget);
      expect(find.text('7 天'), findsOneWidget);
      expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);

      await tester.tap(find.text('土耳其语 · 新版'));
      expect(switched, isTrue);
    });

    testWidgets('连胜为空时右侧不渲染', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: const Scaffold(
            appBar: LightTopBar(courseName: '土耳其语'),
          ),
        ),
      );
      expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
    });
  });

  group('TextTabBar', () {
    testWidgets('渲染全部目的地，点击回报索引', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Scaffold(
            body: TextTabBar(
              items: const [
                TextTabItem(label: '学习'),
                TextTabItem(label: '练习'),
                TextTabItem(label: '我的'),
                TextTabItem(label: '设置'),
              ],
              selectedIndex: 1,
              onTap: taps.add,
            ),
          ),
        ),
      );
      expect(find.text('学习'), findsOneWidget);
      expect(find.text('练习'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);

      await tester.tap(find.text('设置'));
      expect(taps, [3]);

      // 悬浮胶囊默认走轻模糊，几何与模糊强度是接线契约。
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(TextTabBar.overlayExtent, 80);
      expect(TextTabBar.frostSigma, 8);
    });

    testWidgets('选中项有语义标签且文字加重（屏幕阅读器与视觉双信号）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: const Scaffold(
            body: TextTabBar(
              items: [
                TextTabItem(label: '学习'),
                TextTabItem(label: '练习'),
              ],
              selectedIndex: 0,
              onTap: _noop,
            ),
          ),
        ),
      );

      // 语义标签可达（Semantics 的 label/selected 在当前 SDK 无公开
      // getter，选中态改由受光短条 + 文字权重双代理断言）。
      expect(find.bySemanticsLabel('学习'), findsOneWidget);

      final selectedText = tester.widget<Text>(find.text('学习'));
      final unselectedText = tester.widget<Text>(find.text('练习'));
      expect(selectedText.style?.fontWeight, FontWeight.w700);
      expect(unselectedText.style?.fontWeight, FontWeight.w500);

      // 减少动效时不构建 BackdropFilter，退回无模糊的面。
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: TextTabBar(
                items: const [
                  TextTabItem(label: '学习'),
                  TextTabItem(label: '练习'),
                ],
                selectedIndex: 0,
                onTap: _noop,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });
}

void _noop(int index) {}
