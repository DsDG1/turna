import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/home/components/bottom_navigator.dart';
import 'package:turna/views/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late AccessibilityProvider a11y;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    a11y = AccessibilityProvider(prefs);
  });

  Widget wrap(Widget child, {AccessibilityProvider? accessibility}) {
    final tree = MaterialApp(
      theme: TurnaTheme.lightTheme,
      home: Scaffold(
        extendBody: true,
        backgroundColor: TurnaTheme.scaffoldBackground,
        body: const SizedBox.expand(),
        bottomNavigationBar: child,
      ),
    );
    return ChangeNotifierProvider<AccessibilityProvider>.value(
      value: accessibility ?? a11y,
      child: tree,
    );
  }

  testWidgets('renders four labeled destinations', (tester) async {
    var tapped = -1;
    await tester.pumpWidget(
      wrap(
        BottomNavigator(
          currentIndex: 0,
          onPress: (i) => tapped = i,
        ),
      ),
    );

    expect(find.text(AppStrings.commonNavLearn), findsOneWidget);
    expect(find.text(AppStrings.commonNavPlay), findsOneWidget);
    expect(find.text(AppStrings.commonNavProfile), findsOneWidget);
    expect(find.text(AppStrings.commonNavSettings), findsOneWidget);

    await tester.tap(find.text(AppStrings.commonNavPlay));
    expect(tapped, 1);
  });

  testWidgets('selected tab uses filled icon; idle uses outline',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        BottomNavigator(
          currentIndex: 0,
          onPress: (_) {},
        ),
      ),
    );

    expect(find.byIcon(Icons.school_rounded), findsOneWidget);
    expect(find.byIcon(Icons.extension_outlined), findsOneWidget);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('default path avoids backdrop blur', (tester) async {
    await tester.pumpWidget(
      wrap(
        BottomNavigator(
          currentIndex: 0,
          onPress: (_) {},
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ClipRRect), findsWidgets);
  });

  testWidgets('high contrast stays solid without blur', (tester) async {
    await a11y.setHighContrast(true);
    await tester.pumpWidget(
      wrap(
        BottomNavigator(
          currentIndex: 1,
          onPress: (_) {},
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ClipRRect), findsWidgets);
  });

  test('overlayExtent is capsule plus outer gaps, not the home indicator', () {
    expect(
      BottomNavigator.overlayExtent,
      BottomNavigator.capsuleHeight +
          BottomNavigator.bottomGap +
          BottomNavigator.topShadowPad,
    );
  });
}
