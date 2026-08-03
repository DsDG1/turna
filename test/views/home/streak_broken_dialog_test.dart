import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/home/streak_broken_dialog.dart';

void main() {
  group('StreakBrokenDialog', () {
    testWidgets('renders title, body, and got-it button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: true,
                builder: (_) => const StreakBrokenDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.homeStreakBrokenTitle), findsOneWidget);
      expect(find.text(AppStrings.homeStreakBroken), findsOneWidget);
      expect(find.text(AppStrings.commonGotIt), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('got-it dismisses the dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: true,
                builder: (_) => const StreakBrokenDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.commonGotIt));
      await tester.pumpAndSettle();

      expect(find.byType(StreakBrokenDialog), findsNothing);
    });

    testWidgets('barrier tap dismisses when barrierDismissible is true',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: true,
                builder: (_) => const StreakBrokenDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.homeStreakBrokenTitle), findsOneWidget);

      // Tap outside the dialog (barrier).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(StreakBrokenDialog), findsNothing);
    });
  });
}
