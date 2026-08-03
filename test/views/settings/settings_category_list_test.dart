// Widget test: settings category list is grouped and shows subtitles.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/settings/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    settings = SettingsProvider(AppPrefs(sp));
  });

  Widget wrap(Widget child) {
    return ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(home: child),
    );
  }

  testWidgets('category list shows grouped section titles and subtitles',
      (tester) async {
    await tester.pumpWidget(wrap(const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.settingsGroupMain), findsOneWidget);
    expect(find.text(AppStrings.settingsGroupDataAbout), findsOneWidget);
    expect(find.text(AppStrings.settingsGroupLab), findsOneWidget);

    expect(find.text(AppStrings.settingsCategoryAccount), findsOneWidget);
    expect(
      find.text(AppStrings.settingsCategoryAccountSubtitle),
      findsOneWidget,
    );
    expect(
      find.text(AppStrings.settingsCategoryLearningSubtitle),
      findsOneWidget,
    );

    // Fun lab is in its own group; scroll if needed.
    final fun = find.text(AppStrings.settingsCategoryFunLab);
    await tester.ensureVisible(fun);
    await tester.pumpAndSettle();
    expect(fun, findsOneWidget);
    expect(
      find.text(AppStrings.settingsCategoryFunLabSubtitle),
      findsOneWidget,
    );
  });

  testWidgets('tapping a category shows matching app bar title',
      (tester) async {
    await tester.pumpWidget(wrap(const SettingsPage()));
    await tester.pumpAndSettle();

    // Data section only uses action tiles (no GetIt TTS / Anki on build).
    final data = find.text(AppStrings.settingsCategoryData);
    await tester.ensureVisible(data);
    await tester.tap(data);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.settingsTitle), findsNothing);
    expect(find.text(AppStrings.settingsDataSectionTitle), findsWidgets);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.text(AppStrings.settingsExportDataTitle), findsOneWidget);
  });
}
