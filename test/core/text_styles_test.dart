// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';

void main() {
  group('AppTextStyles', () {
    testWidgets('promptMd resolves to onSurface (adaptive text color)',
        (tester) async {
      late BuildContext captured;

      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.darkTheme,
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );

      final style = AppTextStyles.promptMd(captured);
      expect(style.color, TurnaTheme.textPrimaryColor(captured));
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
          theme: TurnaTheme.darkTheme,
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
        isNot(TurnaTheme.textHint),
      );
      expect(
        AppTextStyles.caption(captured).color,
        TurnaTheme.textHintColor(captured),
      );
    });
  });
}
