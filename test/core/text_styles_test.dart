// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:varnamala/core/text_styles.dart';
import 'package:varnamala/views/theme.dart';

void main() {
  group('AppTextStyles', () {
    testWidgets('promptMd resolves to onSurface (adaptive text color)',
        (tester) async {
      late BuildContext captured;

      await tester.pumpWidget(
        MaterialApp(
          theme: VarnamalaTheme.darkTheme,
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );

      final style = AppTextStyles.promptMd(captured);
      expect(style.color, VarnamalaTheme.textPrimaryColor(captured));
      expect(
        style.color,
        Theme.of(captured).colorScheme.onSurface,
      );
    });

    testWidgets('caption uses the hint color helper (not the static token)',
        (tester) async {
      late BuildContext captured;

      await tester.pumpWidget(
        MaterialApp(
          theme: VarnamalaTheme.darkTheme,
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );

      // The dark hint helper must differ from the static near-gray token,
      // proving the caption adapts instead of staying dark-on-dark.
      expect(
        AppTextStyles.caption(captured).color,
        isNot(VarnamalaTheme.textHint),
      );
      expect(
        AppTextStyles.caption(captured).color,
        VarnamalaTheme.textHintColor(captured),
      );
    });

    testWidgets('buttonLabel stays const white on the primary button',
        (tester) async {
      // The check button label is intentionally fixed (white on primary) and
      // must not adapt — guard against accidentally making it context-aware.
      expect(AppTextStyles.buttonLabel.color, Colors.white);
    });
  });
}