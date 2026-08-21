import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/review/recall_outcome.dart';
import 'package:turna/domain/review/review_ledger.dart';
import 'package:turna/views/review/components/binary_recall_bar.dart';
import 'package:turna/views/theme.dart';

void main() {
  group('BinaryRecallBar', () {
    testWidgets('renders without overflow with intervals under TurnaTheme light & dark',
        (tester) async {
      RecallOutcome? outcome;

      for (final theme in [TurnaTheme.lightTheme, TurnaTheme.darkTheme]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: BinaryRecallBar(
                    onOutcome: (val) => outcome = val,
                    forgottenPreview: const ReviewPreview(
                      intervalLabel: '10分钟',
                    ),
                    rememberedPreview: const ReviewPreview(
                      intervalLabel: '4天',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('不记得'), findsOneWidget);
        expect(find.text('10分钟'), findsOneWidget);
        expect(find.text('记得'), findsOneWidget);
        expect(find.text('4天'), findsOneWidget);

        await tester.tap(find.text('不记得'));
        expect(outcome, RecallOutcome.forgotten);

        await tester.tap(find.text('记得'));
        expect(outcome, RecallOutcome.remembered);
      }
    });

    testWidgets('renders without overflow when intervals are null',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: BinaryRecallBar(
                  onOutcome: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('不记得'), findsOneWidget);
      expect(find.text('记得'), findsOneWidget);
    });
  });

  group('elevation regression (styleFrom scales elevation by state)', () {
    testWidgets('recall buttons stay flat in every interaction state',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: BinaryRecallBar(onOutcome: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final style = tester
          .widget<ElevatedButton>(find.byType(ElevatedButton).first)
          .style;
      for (final state in WidgetState.values) {
        expect(
          style?.elevation?.resolve({state}),
          0,
          reason: 'button elevation should stay 0 in $state',
        );
      }
    });

    testWidgets('theme-level ElevatedButton stays flat in light & dark themes',
        (tester) async {
      for (final theme in [TurnaTheme.lightTheme, TurnaTheme.darkTheme]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: ElevatedButton(
                onPressed: () {},
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(ElevatedButton));
        final themeStyle = ElevatedButtonTheme.of(context).style;
        for (final state in WidgetState.values) {
          expect(
            themeStyle?.elevation?.resolve({state}),
            0,
            reason:
                'theme elevation should stay 0 in $state '
                '(${theme.brightness})',
          );
        }
      }
    });
  });
}
