// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:varnamala/views/home/components/stat_app_bar.dart';

void main() {
  group('AnimatedCounter', () {
    testWidgets('animates from the previous value, not from zero',
        (tester) async {
      const style = TextStyle(fontSize: 14);
      const key = ValueKey('counter-under-test');

      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: AnimatedCounter(key: key, target: 5, style: style),
          ),
        ),
      );
      // Let the first frame settle so the initial counter shows 5.
      await tester.pumpAndSettle();
      expect(find.text('5'), findsOneWidget);

      // Bump the target to 8. The tween must start from 5, not 0.
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: AnimatedCounter(key: key, target: 8, style: style),
          ),
        ),
      );

      // The regression we guard against is the old behavior of animating from
      // 0 on every update. Sample a few frames early in the animation: the
      // displayed value must stay at/above the previous value (5), never
      // snap back toward 0.
      for (final step in [
        const Duration(milliseconds: 50),
        const Duration(milliseconds: 100),
        const Duration(milliseconds: 150),
      ]) {
        await tester.pump(step);
        final text = tester.widget<Text>(find.byType(Text)).data;
        final value = int.parse(text!);
        expect(
          value,
          greaterThanOrEqualTo(5),
          reason: 'Counter snapped back toward 0 (from-zero regression). '
              'Saw $value at ${step.inMilliseconds}ms.',
        );
        expect(value, lessThanOrEqualTo(8));
      }
    });

    testWidgets('does not count up on first paint', (tester) async {
      // First render shows the target immediately — no from-zero animation.
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: AnimatedCounter(target: 42, style: TextStyle()),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('42'), findsOneWidget);
    });
  });
}