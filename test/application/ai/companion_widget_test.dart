// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_hint_provider.dart';
import 'package:turna/application/ai/ai_saved_explanations.dart';
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/application/dictionary_search.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/ai_hub_page.dart';
import 'package:turna/views/ai/components/ai_not_configured_panel.dart';
import 'package:turna/views/ai/components/ai_quick_chips.dart';
import 'package:turna/views/dictionary/dictionary_page.dart';
import 'package:turna/views/theme.dart';

void main() {
  testWidgets('quick chips invoke onChip without free typing', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiQuickChipsBar(
            hasUserAnswer: true,
            onChip: (label) => tapped = label,
          ),
        ),
      ),
    );
    expect(find.text(AiQuickChips.simplerExample), findsOneWidget);
    expect(find.text(AiQuickChips.whyWrong), findsOneWidget);
    await tester.tap(find.text(AiQuickChips.simplerExample));
    await tester.pump();
    expect(tapped, AiQuickChips.simplerExample);
  });

  testWidgets('not-configured panel shows configure CTA', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AiNotConfiguredPanel()),
      ),
    );
    expect(find.text(AppStrings.aiNotConfiguredTitle), findsOneWidget);
    expect(find.text(AppStrings.aiNotConfiguredCta), findsOneWidget);
  });

  testWidgets('real AiHubPage is companion-first with authoring retired',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AiEngineConfigHolder()),
            ChangeNotifierProvider(create: (_) => AiRecentTasksProvider()),
            ChangeNotifierProvider(create: (_) => AiExplainPrefsStore()),
          ],
          child: const AiHubPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Companion entry points visible on first screen.
    expect(find.text(AppStrings.aiHubCompanionSection), findsOneWidget);
    expect(find.text(AppStrings.aiHubStartTutorChat), findsOneWidget);
    expect(find.text(AppStrings.aiHubStartDiagnosis), findsOneWidget);
    expect(find.text(AppStrings.aiHubStartSaved), findsOneWidget);
    expect(find.text(AppStrings.aiHubNew), findsOneWidget);

    // Authoring retired from mobile (Plan 3 §19.1): no 创作课程/教材导入
    // entries anywhere on the AI home, not even collapsed.
    expect(find.text(AppStrings.aiHubAuthoringSection), findsNothing);
    expect(find.text(AppStrings.aiHubStartWish), findsNothing);
    expect(find.text(AppStrings.aiHubStartTextbook), findsNothing);
    expect(find.text(AppStrings.aiHubStartTutorChat), findsOneWidget);
    expect(find.text(AppStrings.aiNotConfiguredTitle), findsWidgets);
  });

  testWidgets('saved explanation list/search works via store + UI text',
      (tester) async {
    final store = AiSavedExplanationsStore();
    await store.save(SavedExplanation(
      id: 'a',
      title: '问候',
      body: 'Merhaba is hello',
      source: 'hint',
      createdAt: DateTime(2026, 1, 2),
    ));
    expect(store.search('Merhaba').length, 1);
    expect(store.search('xyz'), isEmpty);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: store,
          child: Scaffold(
            body: Builder(
              builder: (context) {
                final items =
                    context.watch<AiSavedExplanationsStore>().search('');
                return ListView(
                  children: [
                    for (final e in items) Text(e.title),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('问候'), findsOneWidget);
  });

  testWidgets('real DictionaryHitTile shows AI enrich when term present',
      (tester) async {
    final hit = DictionaryHit(
      kind: DictionaryHitKind.vocab,
      id: 'w1',
      title: 'merhaba',
      subtitle: 'hello',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: Scaffold(
          body: DictionaryHitTile(
            hit: hit,
            onSpeak: () {},
          ),
        ),
      ),
    );
    expect(find.byTooltip(AppStrings.aiDictEnrich), findsOneWidget);
    expect(find.text('merhaba'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets(
      'shared AiExplainPrefsStore shapes AiHintProvider system prompt',
      (tester) async {
    final prefs = AiExplainPrefsStore(
      initial: const AiExplainPrefsSnapshot(
        replyLanguage: AiReplyLanguage.en,
        depth: AiExplainDepth.brief,
        allowRevealAnswer: false,
        injectLearnerContext: false,
      ),
    );
    // Mirrors lib/application/providers.dart: prefs first, then
    // AiHintProvider(prefs: ctx.read<AiExplainPrefsStore>()).
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<AiExplainPrefsStore>.value(value: prefs),
            ChangeNotifierProvider<AiHintProvider>(
              create: (ctx) => AiHintProvider(
                engine: AiEngine(
                  AiHttpClient.withClient(_NoopClient()),
                  AiCache.forTest(maxEntries: 0, enabled: false),
                ),
                prefs: ctx.read<AiExplainPrefsStore>(),
              ),
            ),
          ],
          child: Builder(
            builder: (context) {
              // Force create of the shared-wired hint provider.
              context.watch<AiHintProvider>();
              return const SizedBox.shrink(key: Key('hint-ready'));
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final element = tester.element(find.byKey(const Key('hint-ready')));
    final hint = element.read<AiHintProvider>();
    // Prove the provider holds the same store instance as the tree.
    expect(identical(element.read<AiExplainPrefsStore>(), prefs), isTrue);

    const q = AiQuestionContext(
      language: 'Turkish',
      typeLabel: 'Multiple Choice',
      promptLabel: 'Merhaba?',
    );
    final sys = hint.buildSystemPrompt(q);
    expect(sys, contains('English'));
    expect(sys.toLowerCase(), contains('brief'));
    expect(sys.toLowerCase(), contains('do not restate'));

    // Live shared store: mutating prefs is visible on the next prompt build
    // without reconstructing AiHintProvider (the in-lesson path).
    await prefs.setReplyLanguage(AiReplyLanguage.zh);
    await prefs.setDepth(AiExplainDepth.detailed);
    final sys2 = hint.buildSystemPrompt(q);
    expect(sys2, contains('简体中文'));
    expect(sys2.toLowerCase(), contains('detailed'));
  });

  testWidgets('incomplete config holder exposes isComplete false for panel gate',
      (tester) async {
    final holder = AiEngineConfigHolder();
    expect(holder.config.isComplete, isFalse);
  });
}

/// Minimal http.Client that is never called in the prefs-prompt test.
class _NoopClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError('network not used in this test');
  }
}
