import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/settings/components/settings_common.dart';

void main() {
  testWidgets('square switch keeps tap behavior, semantics and square geometry',
      (tester) async {
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
      find.byKey(const Key('settings-square-switch-track')),
    );
    final thumb = tester.widget<Container>(
      find.byKey(const Key('settings-square-switch-thumb')),
    );
    expect((track.decoration! as BoxDecoration).borderRadius, isNull);
    expect(thumb.decoration, isNull);
    expect(tester.getSize(find.byKey(const Key('settings-square-switch'))),
        const Size(56, 48));
    expect(
      tester.getSemantics(find.byKey(const Key('settings-square-switch'))),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasToggledState: true,
        isToggled: false,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.byKey(const Key('settings-square-switch')));
    expect(changed, isTrue);
  });

  testWidgets('settings slider uses a rectangular track and square thumb',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: Scaffold(
          body: SettingsSquareSlider(
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
      tester.element(find.byKey(const Key('settings-square-slider'))),
    );
    expect(theme.trackShape, isA<RectangularSliderTrackShape>());
    expect(theme.thumbShape, isA<SettingsSquareSliderThumbShape>());
    expect(theme.overlayShape, same(SliderComponentShape.noOverlay));
    expect(theme.tickMarkShape, same(SliderTickMarkShape.noTickMark));
  });

  testWidgets('settings theme makes button families square', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: SettingsSquareControlTheme(
          child: Scaffold(
            body: FilledButton(onPressed: () {}, child: const Text('Action')),
          ),
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
      final shape = style!.shape!.resolve(const {})! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.zero);
    }
  });
}
