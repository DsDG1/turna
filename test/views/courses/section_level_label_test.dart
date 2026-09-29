import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/courses/components/section_visuals.dart';

void main() {
  testWidgets('empty level adds no chip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: const Scaffold(
          body: SectionLevelLabel(''),
        ),
      ),
    );
    expect(find.byType(SectionLevelLabel), findsOneWidget);
    expect(find.text('A1'), findsNothing);
  });

  testWidgets('a CEFR tag is shown beside the section name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: Scaffold(
          body: sectionNameWithLevel(
            name: 'Basics',
            level: 'A1',
            style: const TextStyle(fontSize: 17),
          ),
        ),
      ),
    );
    expect(find.text('Basics'), findsOneWidget);
    expect(find.text('A1'), findsOneWidget);
  });
}
