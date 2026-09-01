// Tests: the accessibility capability contract (Plan 2 §4.3) — the provider
// satisfies the interface, and a consumer reading via [accessibilityOf] sees
// the provider's toggles (or neutral defaults without a provider).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/accessibility_capabilities.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccessibilityProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    provider = AccessibilityProvider(AppPrefs(sp));
  });

  testWidgets('provider satisfies the capability contract', (tester) async {
    await provider.setTextScale(150);
    await provider.setReducedMotion(true);
    await provider.setHighContrast(true);
    await provider.setSensoryReduce(true);
    await provider.setFocusMode(true);

    late final AccessibilityCapabilities caps;
    await tester.pumpWidget(
      ChangeNotifierProvider<AccessibilityProvider>.value(
        value: provider,
        child: Builder(
          builder: (context) {
            caps = accessibilityOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(caps.textScalePercent, 150);
    expect(caps.reduceMotion, isTrue);
    expect(caps.highContrast, isTrue);
    expect(caps.quietFeedback, isTrue);
    expect(caps.focusMode, isTrue);
  });

  testWidgets('missing provider resolves to neutral defaults', (tester) async {
    late final AccessibilityCapabilities caps;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          caps = accessibilityOf(context);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(caps.textScalePercent, 100);
    expect(caps.reduceMotion, isFalse);
    expect(caps.focusMode, isFalse);
  });
}
