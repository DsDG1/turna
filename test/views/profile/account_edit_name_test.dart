// Widget test: profile hero "编辑昵称" editor (modal bottom sheet).
//
// The editor moved from the Settings→Account profile card to the profile
// page hero (single identity edit point). Regression guard for the Flutter
// 3.35 Overlay crash that happened when the editor was an AlertDialog with a
// focused TextField: dismissing it while the keyboard was open tripped
// `_overlayChildRenderBox == null` ("already occupied") and
// `InheritedElement._dependents.isEmpty`, because AlertDialog's
// AnimatedPadding (driven by MediaQuery.viewInsets) kept an animation
// mid-flight during route teardown. The editor is a showModalBottomSheet
// (no viewInsets-driven animation on the route), so dismissal is clean.
// These tests pin the save/cancel behaviour.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/profile/widgets/account_app_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.setLocalUser(LocalUser.local);

    if (getIt.isRegistered<AppPrefs>()) {
      await getIt.reset();
    }
    getIt.registerSingleton<AppPrefs>(prefs);
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> pumpHero(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GemsProvider>(
            create: (_) => GemsProvider(prefs),
          ),
          ChangeNotifierProvider<CosmeticProvider>(
            create: (ctx) => CosmeticProvider(prefs, ctx.read<GemsProvider>()),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AccountWidget(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('save updates the displayed nickname', (tester) async {
    await pumpHero(tester);
    expect(find.text('Learner'), findsOneWidget);

    // Open the editor via its tooltip.
    await tester.tap(find.byTooltip(AppStrings.accountEditName));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.accountEditNameTitle), findsOneWidget);

    // Replace the prefilled value and save.
    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.pump();
    await tester.tap(find.text(AppStrings.accountEditNameSave));
    await tester.pumpAndSettle();

    // The sheet is gone and the hero reflects the new name.
    expect(find.text(AppStrings.accountEditNameTitle), findsNothing);
    expect(find.text('Ada'), findsOneWidget);
    expect(prefs.authUser.getValue().displayName, 'Ada');
  });

  testWidgets('cancel dismisses the sheet without changing the name',
      (tester) async {
    await pumpHero(tester);
    expect(find.text('Learner'), findsOneWidget);

    await tester.tap(find.byTooltip(AppStrings.accountEditName));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.accountEditNameTitle), findsNothing);
    expect(find.text('Learner'), findsOneWidget);
    expect(prefs.authUser.getValue().displayName, 'Learner');
  });
}
