import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/ai/engine/ai_engine_config_holder.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/views/play/play_hub_screen.dart';
import 'package:varnamala/views/theme.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
  });

  Future<void> pumpHub(WidgetTester tester, ThemeMode mode) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final srsDao = emptySrsStateDao();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MistakeProvider(prefs)),
          ChangeNotifierProvider(
            create: (_) => SrsProvider(prefs, LessonLinkStore(prefs), srsDao),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                GrammarReviewProvider(prefs, LessonLinkStore(prefs), srsDao),
          ),
          ChangeNotifierProvider(create: (_) => GameProvider.forTesting(prefs)),
          ChangeNotifierProvider<AiEngineConfigHolder>(
            create: (_) => AiEngineConfigHolder(),
          ),
        ],
        child: MaterialApp(
          theme: VarnamalaTheme.lightTheme,
          darkTheme: VarnamalaTheme.darkTheme,
          themeMode: mode,


          home: const Scaffold(body: PlayHubScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('play hub light golden', (tester) async {
    await pumpHub(tester, ThemeMode.light);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/play_hub_light.png'),
    );
  });

  testWidgets('play hub dark golden', (tester) async {
    await pumpHub(tester, ThemeMode.dark);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/play_hub_dark.png'),
    );
  });
}
