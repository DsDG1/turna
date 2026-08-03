import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/theme.dart';

import '../helpers/in_memory_course_db.dart';

/// Lightweight empty-state stand-in for SRS review (full page needs AudioController DI).
class _SrsEmptyReviewBody extends StatelessWidget {
  const _SrsEmptyReviewBody();

  @override
  Widget build(BuildContext context) {
    final due = context.watch<SrsProvider>().dueCount;
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: Center(
        child: Text(
          due == 0 ? 'No words due right now' : '$due words due',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.preferences.setString(LocalStateKeys.srsState, '{}');
  });

  Future<void> pumpSrs(WidgetTester tester, ThemeMode mode) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final srsDao = emptySrsStateDao();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SrsProvider(prefs, LessonLinkStore(prefs), srsDao),
        child: MaterialApp(
          theme: TurnaTheme.lightTheme,
          darkTheme: TurnaTheme.darkTheme,
          themeMode: mode,
          home: const _SrsEmptyReviewBody(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('srs empty light golden', (tester) async {
    await pumpSrs(tester, ThemeMode.light);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/srs_empty_light.png'),
    );
  });

  testWidgets('srs empty dark golden', (tester) async {
    await pumpSrs(tester, ThemeMode.dark);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/srs_empty_dark.png'),
    );
  });
}
