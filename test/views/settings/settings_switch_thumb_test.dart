// Flutter imports:
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/views/settings/widgets/primitives/settings_section.dart';

/// Pixel census of a painted switch: how many pixels are the white thumb and
/// how many are the brand-teal track.
typedef _SwitchPixels = ({int white, int teal});

/// Renders [settingsAdaptiveSwitch] and counts the painted pixels.
///
/// `toImage` / `toByteData` are real async engine calls, so they must run
/// inside [WidgetTester.runAsync]; awaiting them directly in a widget test
/// never completes (the fake async zone does not pump the engine's event
/// loop) and the test hangs forever.
Future<_SwitchPixels> _measureSwitch(
  WidgetTester tester, {
  required bool value,
}) async {
  const key = ValueKey<String>('switch-under-test');

  await tester.pumpWidget(
    MaterialApp(
      theme: TurnaTheme.darkTheme,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: settingsAdaptiveSwitch(value: value, onChanged: (_) {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));

  return (await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int white = 0;
    int teal = 0;
    for (int i = 0; i < data.lengthInBytes; i += 4) {
      final r = data.getUint8(i);
      final g = data.getUint8(i + 1);
      final b = data.getUint8(i + 2);
      final a = data.getUint8(i + 3);
      if (a <= 200) continue;
      if (r > 235 && g > 235 && b > 235) {
        white++;
      } else if ((r - 0x1F).abs() < 24 &&
          (g - 0x72).abs() < 24 &&
          (b - 0x7E).abs() < 24) {
        // brandTeal is #1F727E; tolerance covers antialiasing.
        teal++;
      }
    }
    image.dispose();
    return (white: white, teal: teal);
  }))!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ON switch keeps a white thumb visible on the teal track',
      (tester) async {
    final pixels = await _measureSwitch(tester, value: true);

    // The teal track must be there, otherwise this test proves nothing.
    expect(pixels.teal, greaterThan(200),
        reason: 'ON switch should paint a brand-teal track');
    // Regression guard: the thumb used to be tinted the same teal as the
    // track, so the whole switch collapsed into one solid blob and this
    // count was 0.
    expect(pixels.white, greaterThan(50),
        reason: 'ON switch must show a white thumb; it was swallowed by the '
            'teal track (white pixel count was 0)');
  });

  testWidgets('OFF switch shows a white thumb on the dark track',
      (tester) async {
    final pixels = await _measureSwitch(tester, value: false);
    expect(pixels.white, greaterThan(50),
        reason: 'OFF switch should show a white thumb');
  });

  testWidgets('ON and OFF switches are visually distinct', (tester) async {
    final on = await _measureSwitch(tester, value: true);
    final off = await _measureSwitch(tester, value: false);
    expect(on.white, isNot(off.white),
        reason: 'the two states must not render identically');
  });
}
