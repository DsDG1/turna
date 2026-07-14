import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/views/content_update/content_update_dialog.dart';

void main() {
  Future<ContentUpdateChoice?> pumpAndAwaitChoice(
    WidgetTester tester, {
    required Future<void> Function(Finder) performTap,
  }) async {
    ContentUpdateChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<ContentUpdateChoice>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const ContentUpdateDialog(),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await performTap(find.byType(TextButton));
    await tester.pumpAndSettle();
    return result;
  }

  group('ContentUpdateDialog', () {
    testWidgets('Keep progress returns keepProgress', (tester) async {
      final choice = await pumpAndAwaitChoice(
        tester,
        performTap: (b) => tester.tap(find.text('Keep progress')),
      );
      expect(choice, ContentUpdateChoice.keepProgress);
    });

    testWidgets('Reset progress returns resetProgress', (tester) async {
      final choice = await pumpAndAwaitChoice(
        tester,
        performTap: (b) => tester.tap(find.text('Reset progress')),
      );
      expect(choice, ContentUpdateChoice.resetProgress);
    });

    testWidgets('barrier tap does not dismiss (barrierDismissible:false)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<ContentUpdateChoice>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const ContentUpdateDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Tap the barrier (outside the dialog). Dialog must stay.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Course updated'), findsOneWidget);
    });

    testWidgets('renders both options and the ADR 0002 body text',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<ContentUpdateChoice>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const ContentUpdateDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Course updated'), findsOneWidget);
      expect(find.text('Keep progress'), findsOneWidget);
      expect(find.text('Reset progress'), findsOneWidget);
      expect(find.textContaining('start over'), findsOneWidget);
    });
  });
}