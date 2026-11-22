import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_loader.dart';

void main() {
  testWidgets(
    'TurnaLoader renders page/inline/button and respects disableAnimations',
    (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: TurnaTheme.lightTheme,
            home: Scaffold(
              body: Column(
                children: [
                  TurnaLoader.page(label: '加载中'),
                  TurnaLoader.inline(),
                  TurnaLoader.button(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TurnaLoader), findsNWidgets(3));
      expect(find.text('加载中'), findsOneWidget);
    },
  );
}
