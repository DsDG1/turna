import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_top_bar.dart';

void main() {
  testWidgets('TurnaTopBar displays title, subtitle, and triggers onBack', (
    tester,
  ) async {
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: Scaffold(
          appBar: TurnaTopBar(
            title: '课程管理',
            subtitle: '内置课程与记忆卡牌组',
            onBack: () => popped = true,
            showDivider: true,
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );

    expect(find.text('课程管理'), findsOneWidget);
    expect(find.text('内置课程与记忆卡牌组'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);

    await tester.tap(find.byType(IconButton));
    expect(popped, isTrue);
  });
}
