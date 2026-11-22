import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/settings/components/settings_common.dart';
import 'package:turna/views/widgets/turna_controls.dart';

void main() {
  testWidgets('TurnaSwitch keeps tap behavior, semantics and 4px geometry', (
    tester,
  ) async {
    bool? changed;
    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: settingsAdaptiveSwitch(
              value: false,
              onChanged: (value) => changed = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final track = tester.widget<Container>(
      find.byKey(const Key('turna-switch-track')),
    );
    final thumb = tester.widget<Container>(
      find.byKey(const Key('turna-switch-thumb')),
    );
    expect(
      (track.decoration! as BoxDecoration).borderRadius,
      TurnaTheme.borderRadius,
    );
    expect(
      (thumb.decoration! as BoxDecoration).borderRadius,
      const BorderRadius.all(Radius.circular(2)),
    );
    expect(
      tester.getSize(find.byKey(const Key('turna-switch'))),
      const Size(56, 48),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('turna-switch'))),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasToggledState: true,
        isToggled: false,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.byKey(const Key('turna-switch')));
    expect(changed, isTrue);
  });

  testWidgets('TurnaSlider uses a rectangular track and 4px geometric thumb', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: Scaffold(
          body: TurnaSlider(
            value: 0.5,
            min: 0,
            max: 1,
            divisions: 10,
            activeColor: TurnaTheme.brandTeal,
            inactiveColor: TurnaTheme.divider,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final theme = SliderTheme.of(
      tester.element(find.byKey(const Key('turna-slider'))),
    );
    expect(theme.trackShape, isA<RectangularSliderTrackShape>());
    expect(theme.thumbShape, isA<TurnaSliderThumbShape>());
    expect(theme.overlayShape, same(SliderComponentShape.noOverlay));
    expect(theme.tickMarkShape, same(SliderTickMarkShape.noTickMark));
  });

  testWidgets(
    'global TurnaTheme makes all button families 4px across 4 themes',
    (tester) async {
      for (final themeData in [
        TurnaTheme.lightTheme,
        TurnaTheme.darkTheme,
        TurnaTheme.highContrastLightTheme,
        TurnaTheme.highContrastDarkTheme,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: themeData,
            home: Scaffold(
              body: FilledButton(onPressed: () {}, child: const Text('Action')),
            ),
          ),
        );

        final theme = Theme.of(tester.element(find.byType(FilledButton)));
        final styles = [
          theme.elevatedButtonTheme.style,
          theme.filledButtonTheme.style,
          theme.outlinedButtonTheme.style,
          theme.textButtonTheme.style,
          theme.iconButtonTheme.style,
          theme.segmentedButtonTheme.style,
        ];
        for (final style in styles) {
          final shape =
              style!.shape!.resolve(const {})! as RoundedRectangleBorder;
          expect(shape.borderRadius, TurnaTheme.borderRadius);
        }
      }
    },
  );
}
