import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/turna_select.dart';

enum _Mode { a, b, c }

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: TurnaTheme.lightTheme,
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(8), child: child)),
    );
  }

  testWidgets('TurnaSegmented reports the tapped value and has no check icon',
      (tester) async {
    var selected = _Mode.a;
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return TurnaSegmented<_Mode>(
              selected: selected,
              onChanged: (v) => setState(() => selected = v),
              segments: const [
                ButtonSegment(value: _Mode.a, label: Text('甲')),
                ButtonSegment(value: _Mode.b, label: Text('乙')),
                ButtonSegment(value: _Mode.c, label: Text('丙')),
              ],
            );
          },
        ),
      ),
    );

    expect(find.byIcon(Icons.check), findsNothing);
    await tester.tap(find.text('乙'));
    await tester.pumpAndSettle();
    expect(find.text('乙'), findsOneWidget);
  });

  testWidgets('TurnaChoiceGrid selects a card', (tester) async {
    var selected = _Mode.a;
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return TurnaChoiceGrid<_Mode>(
              selected: selected,
              onSelected: (v) => setState(() => selected = v),
              items: const [
                (_Mode.a, '错题', Icons.history),
                (_Mode.b, '弱词', Icons.quiz),
              ],
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('弱词'));
    await tester.pump();
    expect(find.text('弱词'), findsOneWidget);
  });

  testWidgets('TurnaFilterChip has no checkmark', (tester) async {
    await tester.pumpWidget(
      wrap(
        TurnaFilterChip(
          label: '已标记',
          selected: true,
          onSelected: (_) {},
        ),
      ),
    );
    expect(find.text('已标记'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });
}
