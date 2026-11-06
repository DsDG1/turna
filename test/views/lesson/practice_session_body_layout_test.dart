// PracticeSessionBody 的构图契约：读卡类（无底栏）垂直居中，作答卡贴顶。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/views/lesson/components/practice_session_body.dart';

const _cardKey = ValueKey<String>('probe-card');

Widget _card(double height) => SizedBox(
      key: _cardKey,
      height: height,
      child: const ColoredBox(color: Colors.transparent),
    );

Future<void> _pump(
  WidgetTester tester, {
  required bool autoAdvance,
  required double cardHeight,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PracticeSessionBody(
          autoAdvance: autoAdvance,
          onAdvance: () {},
          child: _card(cardHeight),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('读卡类把内容垂直居中 —— 画布不再下半截空着', (tester) async {
    await _pump(tester, autoAdvance: true, cardHeight: 200);

    final rect = tester.getRect(find.byKey(_cardKey));
    // 400x800 画布，200 高的卡居中 → 顶边 300、底边 500。
    expect(rect.top, closeTo(300, 1));
    expect(rect.bottom, closeTo(500, 1));
  });

  testWidgets('作答卡保持贴顶 —— 解析长出时不会整卡上跳', (tester) async {
    await _pump(tester, autoAdvance: false, cardHeight: 200);

    final rect = tester.getRect(find.byKey(_cardKey));
    // 顶部 8 是 scroller 的呼吸位（见 practice_session_body 的 padding 注释）。
    expect(rect.top, closeTo(8, 1));
  });

  testWidgets('内容超出一屏时居中失效，仍可滚动', (tester) async {
    await _pump(tester, autoAdvance: true, cardHeight: 1200);

    final rect = tester.getRect(find.byKey(_cardKey));
    expect(rect.top, closeTo(8, 1));
    expect(rect.height, 1200);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_cardKey)).top, lessThan(0));
    expect(tester.takeException(), isNull);
  });
}
