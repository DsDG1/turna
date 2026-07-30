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

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
  });

  testWidgets('renders play hub sections', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final srsDao = emptySrsStateDao();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => MistakeProvider(prefs),
          ),
          ChangeNotifierProvider(
            create: (_) => SrsProvider(prefs, LessonLinkStore(prefs), srsDao),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                GrammarReviewProvider(prefs, LessonLinkStore(prefs), srsDao),
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

    expect(find.text('快速练习'), findsOneWidget);
    expect(find.text('今日重点'), findsOneWidget);
    expect(find.text('复习中心'), findsOneWidget);
    expect(find.text('工具'), findsOneWidget);
    expect(find.text('错题复习'), findsOneWidget);
    expect(find.text('复习'), findsNWidgets(2));
    expect(find.text('语法复习'), findsOneWidget);
    expect(find.text('薄弱单词'), findsOneWidget);
    expect(find.text('Anki 复习'), findsOneWidget);
    expect(find.text('词典'), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('你的最佳'), findsNothing);
    expect(find.text('总经验值'), findsNothing);

    // 第三张今日重点卡需要左滑才会构建
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('每日挑战'), findsOneWidget);
  });
}
