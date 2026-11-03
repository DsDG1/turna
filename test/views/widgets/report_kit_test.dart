// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/report_kit.dart';

/// 报告构图套件（P2 组件）的行为契约：空数据让位、构成条只画正值、
/// 图表语义名必达。数值正确性属 painter 内部，由 @Preview 肉眼核对。
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: Scaffold(body: child),
      );

  group('ReportMetricHeader', () {
    testWidgets('标签、数字、单位与副行齐全', (tester) async {
      await tester.pumpWidget(
        wrap(const ReportMetricHeader(
          label: '近 30 天复习',
          value: '412',
          unit: '张',
          caption: '比上一段多 18%',
        )),
      );
      expect(find.text('近 30 天复习'), findsOneWidget);
      expect(find.text('412'), findsOneWidget);
      expect(find.text('张'), findsOneWidget);
      expect(find.text('比上一段多 18%'), findsOneWidget);
    });
  });

  group('ReportCompositionBar', () {
    testWidgets('只画正值段，图例带值', (tester) async {
      await tester.pumpWidget(
        wrap(const ReportCompositionBar(
          segments: [
            ReportSegment(label: '单词', value: 12, color: TurnaTheme.brandTeal),
            ReportSegment(label: '语法', value: 0, color: TurnaTheme.brandSky),
            ReportSegment(
                label: '错题', value: 6, color: TurnaTheme.anatolianClay),
          ],
        )),
      );
      expect(find.text('单词'), findsOneWidget);
      expect(find.text('语法'), findsNothing);
      expect(find.text('错题'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('全零段整件让位', (tester) async {
      await tester.pumpWidget(
        wrap(const ReportCompositionBar(
          segments: [
            ReportSegment(label: '空', value: 0, color: TurnaTheme.brandTeal),
          ],
        )),
      );
      expect(find.text('空'), findsNothing);
    });
  });

  group('ReportBarChart', () {
    testWidgets('空数据让位；有数据时语义名可达', (tester) async {
      await tester.pumpWidget(
        wrap(const ReportBarChart(semanticsLabel: '空图', bars: [])),
      );
      expect(find.bySemanticsLabel('空图'), findsNothing);

      await tester.pumpWidget(
        wrap(const ReportBarChart(
          semanticsLabel: '每周复习量',
          bars: [
            ReportBar(label: '一', value: 40),
            ReportBar(label: '二', value: 68),
          ],
        )),
      );
      expect(
        find.descendant(
          of: find.bySemanticsLabel('每周复习量'),
          matching: find.byType(SizedBox),
        ),
        findsWidgets,
      );
    });
  });

  group('ReportLineChart', () {
    testWidgets('少于两点让位', (tester) async {
      await tester.pumpWidget(
        wrap(const ReportLineChart(
          semanticsLabel: '折线',
          points: [ReportPoint(label: '10-28', value: 0.7)],
        )),
      );
      expect(find.bySemanticsLabel('折线'), findsNothing);
    });

    testWidgets('多点时渲染语义名', (tester) async {
      await tester.pumpWidget(
        wrap(const ReportLineChart(
          semanticsLabel: '记忆保持率',
          points: [
            ReportPoint(label: '10-28', value: 0.72),
            ReportPoint(label: '10-29', value: 0.81),
            ReportPoint(label: '10-30', value: 0.76),
          ],
        )),
      );
      expect(find.bySemanticsLabel('记忆保持率'), findsOneWidget);
    });
  });

  group('ReportHeatmap', () {
    testWidgets('格数 = levels 长度（不足一行补轨道格）', (tester) async {
      await tester.pumpWidget(
        wrap(const ReportHeatmap(
          semanticsLabel: '学习热图',
          columns: 5,
          levels: [0, 1, 2, 1, 0, 3, 2],
        )),
      );
      final cells = find.descendant(
        of: find.byType(ReportHeatmap),
        matching: find.byType(Container),
      );
      // 7 个数据格补齐到 2×5 = 10 格。
      expect(tester.widgetList(cells).length, 10);
    });

    testWidgets('空数据让位（不渲染任何格子）', (tester) async {
      await tester.pumpWidget(
        wrap(const ReportHeatmap(semanticsLabel: '热图', columns: 5, levels: [])),
      );
      final cells = find.descendant(
        of: find.byType(ReportHeatmap),
        matching: find.byType(Container),
      );
      expect(cells, findsNothing);
    });
  });

  group('ReportDefinitionList', () {
    testWidgets('行与发丝线（n-1 条）渲染', (tester) async {
      await tester.pumpWidget(
        wrap(const ReportDefinitionList(
          rows: [
            ReportDefinitionRow(label: '平均间隔', value: '9.4 天'),
            ReportDefinitionRow(label: '主动来源', value: '3 个'),
            ReportDefinitionRow(label: '今日已写入', value: '21 条'),
          ],
        )),
      );
      expect(find.text('平均间隔'), findsOneWidget);
      expect(find.text('21 条'), findsOneWidget);
      expect(find.byType(Divider), findsNWidgets(2));
    });
  });
}
