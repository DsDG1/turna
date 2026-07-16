import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/views/play/play_hub_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
  });

  testWidgets('renders play hub cards and stats section', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => MistakeProvider(prefs),
          ),
          ChangeNotifierProvider(
            create: (_) => SrsProvider(prefs, LessonLinkStore(prefs)),
          ),
          ChangeNotifierProvider(
            create: (_) => GrammarReviewProvider(prefs, LessonLinkStore(prefs)),
          ),
          ChangeNotifierProvider(
            create: (_) => GameProvider.forTesting(prefs),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PlayHubScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Quick Play'), findsOneWidget);
    expect(find.text('Mistake Review'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Grammar Review'), findsOneWidget);
    expect(find.text('Daily Challenge'), findsOneWidget);
    expect(find.text('Weak Words'), findsOneWidget);
    expect(find.text('Dictionary'), findsOneWidget);
    expect(find.text('Your Best'), findsOneWidget);
    expect(find.text('Total XP'), findsOneWidget);
  });
}
