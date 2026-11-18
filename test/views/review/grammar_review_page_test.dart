import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/domain/review/review_grade.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/review/grammar_review_page.dart';

import '../../helpers/in_memory_course_db.dart';

class _FlakyGrammarReviewProvider extends GrammarReviewProvider {
  _FlakyGrammarReviewProvider(super.appPrefs, super.linkStore, super.srsDao);

  bool failRate = true;
  bool failUndo = true;

  @override
  Future<SrsWord?> reviewWithQuality(String id, ReviewGrade grade) async {
    if (failRate) {
      throw StateError('grammar rate failed');
    }
    return state[id];
  }

  @override
  Future<bool> rollbackGrammarPoint(String id, SrsWord? previous) async {
    if (failUndo) {
      throw StateError('grammar undo failed');
    }
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late AppPrefs appPrefs;
  late _FlakyGrammarReviewProvider grammar;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    appPrefs = AppPrefs(sp);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<Set<InteractionRenderer>>(
      const <InteractionRenderer>{},
    );

    final dao = emptySrsStateDao();
    grammar = _FlakyGrammarReviewProvider(
      appPrefs,
      LessonLinkStore(appPrefs),
      dao,
    );
    grammar.registerAll(const ['g1', 'g2']);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('rate and undo failures show snackbar and do not wedge buttons',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GrammarReviewProvider>.value(value: grammar),
          ChangeNotifierProvider<AccessibilityProvider>.value(
            value: AccessibilityProvider(appPrefs),
          ),
        ],
        child: MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: const GrammarReviewPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('g1'), findsOneWidget);
    await tester.tap(find.text(AppStrings.reviewGrammarShowExplanation));
    await tester.pumpAndSettle();

    // First rating throws -> shows SnackBar and stays on g1 with buttons enabled.
    await tester.tap(find.text(AppStrings.reviewKnowIt));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.grammarRateFailed), findsOneWidget);
    expect(find.text('g1'), findsOneWidget);

    // Retry rating succeeds -> advances to g2.
    grammar.failRate = false;
    await tester.tap(find.text(AppStrings.reviewKnowIt));
    await tester.pumpAndSettle();
    expect(find.text('g2'), findsOneWidget);

    // Undo throws -> shows SnackBar, stays on g2, and resets busy state.
    await tester.tap(find.byTooltip(AppStrings.commonUndoLastCard));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.grammarRateFailed), findsOneWidget);
    expect(find.text('g2'), findsOneWidget);
    final undoButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(AppStrings.commonUndoLastCard),
        matching: find.byType(IconButton),
      ),
    );
    expect(undoButton.onPressed, isNotNull);
  });
}
