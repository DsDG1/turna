import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/settings/widgets/settings_reminder_section.dart';
import 'package:turna/views/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    settings = SettingsProvider(prefs);
    await settings.setDailyReminderEnabled(true);
  });

  Future<void> pumpReminder(WidgetTester tester, ThemeMode mode) async {
    await tester.binding.setSurfaceSize(const Size(400, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          theme: TurnaTheme.lightTheme,
          darkTheme: TurnaTheme.darkTheme,
          themeMode: mode,
          home: Scaffold(
            body: ListView(
              children: const [
                SettingsSectionTitle(
                  title: 'Learning',
                  icon: Icons.menu_book_rounded,
                ),
                SettingsCard(children: [SettingsDailyReminderTile()]),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('settings reminder light golden', (tester) async {
    await pumpReminder(tester, ThemeMode.light);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_reminder_light.png'),
    );
  });

  testWidgets('settings reminder dark golden', (tester) async {
    await pumpReminder(tester, ThemeMode.dark);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_reminder_dark.png'),
    );
  });
}
