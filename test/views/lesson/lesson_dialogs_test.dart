import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/views/lesson/components/lesson_dialogs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('showLessonCompletionDialog shows a celebration title',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  showLessonCompletionDialog(
                    context: context,
                    isMounted: () => true,
                    random: Random(0),
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump(); // start delay
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    // One of the three celebration titles from lessonCelebrationStyles.
    final titles = lessonCelebrationStyles.map((s) => s.title).toList();
    expect(
      titles.any((t) => find.text(t).evaluate().isNotEmpty),
      isTrue,
      reason: 'expected one of $titles',
    );
  });
}
