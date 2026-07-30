// Widget test: Account "管理数据" navigates via constructor callback (no static).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/auth/local_user.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/views/settings/widgets/settings_account_section.dart';

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

  testWidgets('管理数据 tile invokes onNavigateToData callback', (tester) async {
    var navigated = false;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameProvider>(
            create: (_) => GameProvider.forTesting(prefs),
          ),
          ChangeNotifierProvider<MistakeProvider>(
            create: (_) => MistakeProvider(prefs),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsAccountSection(
                onNavigateToData: () => navigated = true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Action tile is below the fold on the default 800×600 test surface.
    final target = find.text(AppStrings.accountDataManagementSubtitle);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump();

    expect(navigated, isTrue);
  });
}
