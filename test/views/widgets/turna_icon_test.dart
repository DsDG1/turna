import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/views/widgets/turna_icon.dart';

void main() {
  test('every TurnaIconId resolves to an existing SVG asset on disk', () {
    final missing = <String>[];
    for (final id in TurnaIconId.values) {
      if (!File(id.assetPath).existsSync()) {
        missing.add('${id.name} -> ${id.assetPath}');
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'Missing Bauhaus SVG icon files:\n${missing.join('\n')}',
    );
  });

  testWidgets(
    'TurnaIcon renders and respects IconTheme & explicit size/color',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: const Scaffold(
            body: IconTheme(
              data: IconThemeData(size: 20, color: TurnaTheme.brandTeal),
              child: TurnaIcon(TurnaIconId.book, semanticLabel: 'Book'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TurnaIcon), findsOneWidget);
      expect(find.bySemanticsLabel('Book'), findsOneWidget);
    },
  );
}
