// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_prompt_catalog.dart';
import 'package:turna/application/ai/ai_prompt_overrides.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

void main() {
  const prefs = AiExplainPrefsSnapshot();

  group('AiPromptCatalog', () {
    test('free chat default carries persona, prefs rules and the mode line',
        () {
      final prompt = AiPromptCatalog.freeChat(
        language: 'Turkish',
        modeLine: AiPromptCatalog.freeChatModeQa,
        prefs: prefs,
      );
      expect(prompt, contains('language-learning companion for Turkish'));
      expect(prompt, contains('Never output course section/unit/lesson JSON'));
      expect(prompt, contains('Mode: Q&A'));
      // 讲解偏好必须以规则块形式在场，否则「回复语言/深度」设置形同虚设。
      expect(prompt, contains('Reply language:'));
      expect(prompt, contains('Depth: standard'));
    });

    test('learner context is only injected when the pref allows it', () {
      final withContext = AiPromptCatalog.freeChat(
        language: 'Turkish',
        modeLine: AiPromptCatalog.freeChatModeQa,
        prefs: prefs,
        learnerContextBlock: 'My weak words: -mek, -mak',
      );
      expect(withContext, contains('My weak words'));

      final blocked = AiPromptCatalog.freeChat(
        language: 'Turkish',
        modeLine: AiPromptCatalog.freeChatModeQa,
        prefs: const AiExplainPrefsSnapshot(injectLearnerContext: false),
        learnerContextBlock: 'My weak words: -mek, -mak',
      );
      expect(blocked, isNot(contains('My weak words')));
    });

    test('an empty override leaves the default byte-identical', () {
      final plain = AiPromptCatalog.cardExplain(
        language: 'Turkish',
        prefs: prefs,
      );
      final blank = AiPromptCatalog.cardExplain(
        language: 'Turkish',
        prefs: prefs,
        override: '   \n ',
      );
      expect(blank, plain);
    });

    test('override is appended, never replaces the default', () {
      final prompt = AiPromptCatalog.cardExplain(
        language: 'Turkish',
        prefs: prefs,
        override: 'Always add one example sentence.',
      );
      expect(prompt, startsWith('You are a language-learning companion'));
      expect(prompt, contains('the card answer is authoritative'));
      expect(prompt, contains('Additional requirements from the learner'));
      expect(prompt, contains('Always add one example sentence.'));
      // 追加块必须在默认文本之后。
      expect(
        prompt.indexOf('Additional requirements'),
        greaterThan(prompt.indexOf('card answer is authoritative')),
      );
    });

    test('JSON features keep their schema contract even when customised', () {
      final dict = AiPromptCatalog.dictionary(
        language: 'Turkish',
        prefs: prefs,
        override: 'Mention the etymology when useful.',
      );
      expect(dict, contains('"expandedGloss":string'));
      expect(dict, contains('Respond with ONLY a JSON object'));

      final diag = AiPromptCatalog.diagnosis(
        language: 'Turkish',
        prefs: prefs,
        override: 'Sound encouraging.',
      );
      expect(diag, contains('"weakAreas"'));
    });

    test('hint switches the reveal policy with the answer state', () {
      final hidden = AiPromptCatalog.hint(
        language: 'Turkish',
        typeLabel: 'multipleChoice',
        allowReveal: false,
        prefs: prefs,
      );
      expect(hidden, contains('Do not directly restate the correct answer'));
      expect(hidden, contains('distractors'));

      final revealed = AiPromptCatalog.hint(
        language: 'Turkish',
        typeLabel: 'multipleChoice',
        allowReveal: true,
        prefs: prefs,
      );
      expect(revealed, contains('you may compare'));
      expect(revealed,
          isNot(contains('Do not directly restate the correct answer')));
    });

    test('preview labels runtime-only blocks instead of faking them', () {
      final preview = AiPromptCatalog.preview(
        feature: AiPromptFeature.hint,
        language: 'Turkish',
        prefs: prefs,
      );
      expect(preview, contains('运行时注入'));
    });

    // 回归：Anki 卡片的语言由导入的牌组决定，不由课程决定。从前这里一律
    // 套「for Turkish」，导入日语 / 英语牌组后 AI 仍把卡片当土耳其语讲。
    test('card explain without a language asks the model to infer it', () {
      final prompt = AiPromptCatalog.cardExplain(
        language: null,
        prefs: prefs,
      );
      expect(prompt, contains('imported Anki deck'));
      expect(prompt, contains('infer it from the card text'));
      expect(prompt, isNot(contains('companion for Turkish')));
      // 产品边界不因语言未知而放松。
      expect(prompt, contains('the card answer is authoritative'));
      expect(prompt, contains('Never output course section JSON'));

      // 空串与 null 同义：上游传 '' 时不能变成「for 」这种半句话。
      final blank = AiPromptCatalog.cardExplain(language: '  ', prefs: prefs);
      expect(blank, prompt);
    });

    test('card explain for a course card still names the language', () {
      final prompt = AiPromptCatalog.cardExplain(
        language: 'Turkish',
        prefs: prefs,
      );
      expect(prompt,
          startsWith('You are a language-learning companion for Turkish.'));
      expect(prompt, isNot(contains('imported Anki deck')));
    });

    // 面板要能列出「全部」可改的提示词：每个功能都得有非空默认文本，且追加
    // 要求能生效——缺一条就会在面板里显示空白。
    test('every feature has a default text that accepts an override', () {
      for (final feature in AiPromptFeature.values) {
        final base = AiPromptCatalog.preview(
          feature: feature,
          language: 'Turkish',
          prefs: prefs,
        );
        expect(base.trim(), isNotEmpty, reason: '${feature.name} 默认文本为空');

        final customised = AiPromptCatalog.preview(
          feature: feature,
          language: 'Turkish',
          prefs: prefs,
          override: 'Keep sentences short.',
        );
        expect(customised, contains('Keep sentences short.'),
            reason: '${feature.name} 的追加要求没有生效');
        expect(customised, startsWith(base));
      }
    });

    test('course generation differs only by the conversation clause', () {
      final plain = AiPromptCatalog.courseGeneration();
      final convo = AiPromptCatalog.courseGeneration(fromConversation: true);
      expect(plain, contains('You output ONLY valid JSON'));
      expect(plain, isNot(contains('conversation history')));
      expect(convo, contains('conversation history'));
      expect(convo, startsWith(plain));
    });
  });

  group('AiPromptOverridesStore', () {
    setUp(() {
      getIt.reset();
      AiPromptOverridesStore.resetFallbackForTest();
    });
    tearDown(() {
      getIt.reset();
      AiPromptOverridesStore.resetFallbackForTest();
    });

    test('keeps one in-process instance when GetIt is not registered', () {
      final a = AiPromptOverridesStore.resolve();
      final b = AiPromptOverridesStore.resolve();
      expect(identical(a, b), isTrue, reason: 'provider 与面板必须看到同一份覆盖文本');
    });

    test('empty text means "no override", not "override with blank"', () async {
      final store = AiPromptOverridesStore();
      await store.setText(AiPromptFeature.freeChat, 'be terse');
      expect(store.isOverridden(AiPromptFeature.freeChat), isTrue);

      await store.setText(AiPromptFeature.freeChat, '   ');
      expect(store.isOverridden(AiPromptFeature.freeChat), isFalse);
      expect(store.textFor(AiPromptFeature.freeChat), '');
    });

    // 面板上的「全部恢复默认」：一次清掉所有功能的追加文本，默认提示词不动。
    test('clearAll drops every feature at once', () async {
      final store = AiPromptOverridesStore();
      await store.setText(AiPromptFeature.freeChat, 'a');
      await store.setText(AiPromptFeature.diagnosis, 'b');
      await store.setText(AiPromptFeature.courseGeneration, 'c');
      expect(store.customised, hasLength(3));

      await store.clearAll();

      expect(store.customised, isEmpty);
      expect(store.textFor(AiPromptFeature.diagnosis), '');
      // 清完仍是「默认」，不是「空提示词」。
      final base = AiPromptCatalog.preview(
        feature: AiPromptFeature.diagnosis,
        language: 'Turkish',
        prefs: const AiExplainPrefsSnapshot(),
      );
      expect(base, contains('language-learning coach'));
    });

    test('overlong text is truncated to the documented cap', () async {
      final store = AiPromptOverridesStore();
      await store.setText(
        AiPromptFeature.dictionary,
        'x' * (kAiPromptOverrideMaxChars + 500),
      );
      expect(store.textFor(AiPromptFeature.dictionary).length,
          kAiPromptOverrideMaxChars);
    });

    test('persists per feature and reloads from prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      getIt.registerLazySingleton<AppPrefs>(() => AppPrefs(sp));

      final store = AiPromptOverridesStore();
      await store.setText(AiPromptFeature.freeChat, 'use short sentences');
      await store.setText(AiPromptFeature.hint, 'never mention grammar terms');

      final reloaded = AiPromptOverridesStore();
      await reloaded.load();
      expect(reloaded.textFor(AiPromptFeature.freeChat), 'use short sentences');
      expect(reloaded.textFor(AiPromptFeature.hint),
          'never mention grammar terms');
      expect(reloaded.textFor(AiPromptFeature.diagnosis), '');
      expect(reloaded.customised, hasLength(2));

      await reloaded.clear(AiPromptFeature.freeChat);
      final third = AiPromptOverridesStore();
      await third.load();
      expect(third.textFor(AiPromptFeature.freeChat), '');
      expect(
          third.textFor(AiPromptFeature.hint), 'never mention grammar terms');
    });
  });
}
