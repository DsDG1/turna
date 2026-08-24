// Widget test: personalization owns cosmetics/goals, not duplicate data links.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/settings/widgets/settings_account_section.dart';

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

  testWidgets('个性化页只保留装扮与每日目标', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameProvider>(
            create: (_) => GameProvider.forTesting(prefs),
          ),
          ChangeNotifierProvider<MistakeProvider>(
            create: (_) => MistakeProvider(prefs),
          ),
          ChangeNotifierProvider<GemsProvider>(
            create: (_) => GemsProvider(prefs),
          ),
          ChangeNotifierProvider<CosmeticProvider>(
            create: (ctx) => CosmeticProvider(prefs, ctx.read<GemsProvider>()),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: const SettingsAccountSection(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.cosmeticsTitle), findsOneWidget);
    expect(find.text(AppStrings.accountGoalsTitle), findsOneWidget);
    expect(find.text(AppStrings.accountDataManagementSubtitle), findsNothing);
    expect(find.text(AppStrings.accountResetTitle), findsNothing);
  });
}
