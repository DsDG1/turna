import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/views/widgets/turna_reading_layout.dart';

void main() {
  testWidgets('TurnaReadingLayout renders 4px paper card, header and badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: const Scaffold(
          body: Column(
            children: [
              TurnaReadingSectionHeader(
                indexLabel: '01',
                title: '隐私原则',
                subtitle: '离线优先',
              ),
              TurnaReadingCard(
                child: TurnaReadingBadge(
                  label: '本地存储',
                  icon: TurnaIconId.shield,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('01'), findsOneWidget);
    expect(find.text('隐私原则'), findsOneWidget);
    expect(find.text('本地存储'), findsOneWidget);
  });
}
