import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/home/components/scroll_hide_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccessibilityProvider a11y;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    a11y = AccessibilityProvider(AppPrefs(sp));
  });

  Widget wrap(Widget child) {
    return ChangeNotifierProvider<AccessibilityProvider>.value(
      value: a11y,
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  Finder descendantOfBar(Type type) => find.descendant(
        of: find.byType(ScrollHideBar),
        matching: find.byType(type),
      );

  testWidgets('shown bar is tappable and not translated', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ScrollHideBar(
          hidden: false,
          child: SizedBox(width: 40, height: 40),
        ),
      ),
    );

    final ignore = tester.widget<IgnorePointer>(descendantOfBar(IgnorePointer));
    expect(ignore.ignoring, isFalse);

    final slide = tester.widget<AnimatedSlide>(descendantOfBar(AnimatedSlide));
    expect(slide.offset, Offset.zero);
  });

  testWidgets('hidden bar ignores pointers and slides down', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ScrollHideBar(
          hidden: true,
          child: SizedBox(width: 40, height: 40),
        ),
      ),
    );

    final ignore = tester.widget<IgnorePointer>(descendantOfBar(IgnorePointer));
    expect(ignore.ignoring, isTrue);

    final slide = tester.widget<AnimatedSlide>(descendantOfBar(AnimatedSlide));
    expect(slide.offset.dy, greaterThan(0));
  });

  testWidgets('reduced motion snaps with zero duration', (tester) async {
    await a11y.setReducedMotion(true);
    await tester.pumpWidget(
      wrap(
        const ScrollHideBar(
          hidden: true,
          child: SizedBox(width: 40, height: 40),
        ),
      ),
    );

    final slide = tester.widget<AnimatedSlide>(descendantOfBar(AnimatedSlide));
    expect(slide.duration, Duration.zero);
  });
}
