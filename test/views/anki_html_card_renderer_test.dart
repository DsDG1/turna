// Widget tests for AnkiHtmlCardRenderer (fidelity track, 阶段 2). On the
// desktop test host AnkiHtmlCardView uses the text fallback (no WebView impl),
// so these tests assert on the stripped front/back text + the four-grade
// flow - the same UX contract as AnkiCardRenderer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/lesson/components/interactions/anki_html_card_renderer.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    settings = SettingsProvider(AppPrefs(preferences));
  });

  const interaction = Interaction.ankiHtmlCard(
    id: 'anki-html-1',
    frontHtml: '<p>What is the capital of France?</p>',
    backHtml: '<p>Paris</p>',
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    required OnInteractionSubmit onSubmit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: Scaffold(
            body: AnkiHtmlCardRenderer().build(
              interaction,
              const InteractionState(),
              onSubmit,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows front text, reveals back on "Show Answer"',
      (tester) async {
    await pumpCard(
      tester,
      onSubmit: (_, {userAnswerText, reviewQuality}) {},
    );
    expect(find.textContaining('capital of France'), findsOneWidget);
    // Back is hidden before reveal.
    expect(find.textContaining('Paris'), findsNothing);

    await tester.tap(find.text('显示答案'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Paris'), findsOneWidget);
  });

  testWidgets('Remembered submits success with quality 4', (tester) async {
    final results = <(bool, int?)>[];
    await pumpCard(
      tester,
      onSubmit: (correct, {userAnswerText, reviewQuality}) =>
          results.add((correct, reviewQuality)),
    );
    await tester.tap(find.text('显示答案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记得'));
    expect(results, [(true, 4)]);
  });

  testWidgets('Forgotten submits failure with quality 1', (tester) async {
    final results = <(bool, int?)>[];
    await pumpCard(
      tester,
      onSubmit: (correct, {userAnswerText, reviewQuality}) =>
          results.add((correct, reviewQuality)),
    );
    await tester.tap(find.text('显示答案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不记得'));
    expect(results, [(false, 1)]);
  });

  testWidgets('card surface toggles back and front without submitting',
      (tester) async {
    final results = <(bool, int?)>[];
    await pumpCard(
      tester,
      onSubmit: (correct, {userAnswerText, reviewQuality}) =>
          results.add((correct, reviewQuality)),
    );

    final surface = find.byKey(const ValueKey('anki-html-flip-card-surface'));
    await tester.tap(surface);
    await tester.pumpAndSettle();
    expect(find.textContaining('Paris'), findsOneWidget);

    await tester.tap(surface);
    await tester.pumpAndSettle();
    expect(find.textContaining('capital of France'), findsOneWidget);
    expect(find.textContaining('Paris'), findsNothing);
    expect(results, isEmpty);
  });

  test('handlesType is AnkiHtmlCard', () {
    expect(AnkiHtmlCardRenderer().handlesType, AnkiHtmlCard);
  });
}
