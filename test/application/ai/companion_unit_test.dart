// Dart imports:
import 'dart:async';
import 'dart:convert';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Project imports:
import 'package:turna/application/ai/ai_diagnosis_provider.dart';
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_hint_provider.dart';
import 'package:turna/application/ai/ai_saved_explanations.dart';
import 'package:turna/application/ai/ai_tutor_chat_provider.dart';
import 'package:turna/application/ai/dictionary_ai_provider.dart';
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/application/ai/engine/ai_provider_preset.dart';
import 'package:turna/application/ai/hint_genres.dart';
import 'package:turna/application/ai/learner_ai_context.dart';

http.Response _textResponse(String content) {
  final body = jsonEncode({
    'choices': [
      {
        'message': {'role': 'assistant', 'content': content},
      },
    ],
  });
  return http.Response.bytes(
    utf8.encode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

AiEngineConfig _engineConfig() => const AiEngineConfig(
      preset: kCustomPreset,
      apiKey: 'k',
      modelChat: 'm',
      modelJson: 'm',
      customBaseUrl: 'https://example.test/v1',
      cacheEnabled: false,
    );

AiEngine _engine(http.Client client) => AiEngine(
      AiHttpClient.withClient(client),
      AiCache.forTest(maxEntries: 0, enabled: false),
    );

AiQuestionContext _ctx({String? userAnswer}) => AiQuestionContext(
      language: 'Turkish',
      typeLabel: 'Multiple Choice',
      promptLabel: 'What does Merhaba mean?',
      optionsLabel: 'Hello / Goodbye / Thanks',
      userAnswer: userAnswer,
    );

void main() {
  group('LearnerAiContext', () {
    test('empty context has no lists', () {
      final c = LearnerAiContext.empty('Turkish');
      expect(c.isEmpty, isTrue);
      expect(c.languageName, 'Turkish');
    });

    test('dedupes and truncates prompt block', () {
      final c = LearnerAiContext.assemble(
        languageName: 'Turkish',
        cefrLevel: 'A1',
        recentMistakeSummaries: [
          'hello',
          'Hello',
          'world',
          for (var i = 0; i < 20; i++) 'm$i',
        ],
        weakTerms: ['a', 'a', 'b'],
        maxMistakes: 8,
        maxWeakTerms: 8,
      );
      final block = c.toPromptBlock(maxChars: 120);
      expect(block.contains('[LearnerContext]'), isTrue);
      expect(block.contains('CEFR: A1'), isTrue);
      // Deduped hello once.
      expect(RegExp(r'hello', caseSensitive: false).allMatches(block).length,
          lessThanOrEqualTo(2));
      expect(block.length, lessThanOrEqualTo(120));
      if (block.length == 120 || block.endsWith('…')) {
        expect(block.endsWith('…'), isTrue);
      }
    });

    test('summarizeMistake truncates long lines', () {
      final s = LearnerAiContext.summarizeMistake(
        prompt: 'x' * 200,
        userAnswer: 'y',
        maxLen: 40,
      );
      expect(s.length, lessThanOrEqualTo(40));
      expect(s.endsWith('…'), isTrue);
    });
  });

  group('AiErrorMapper', () {
    test('maps cancelled / incomplete / auth / rate / parse', () {
      expect(AiErrorMapper.map(const AiCancelled()).kind, AiErrorKind.cancelled);
      expect(
        AiErrorMapper.map(Exception(
                'AI config incomplete: please fill in Base URL / API Key / Model.'))
            .kind,
        AiErrorKind.notConfigured,
      );
      expect(AiErrorMapper.map(Exception('HTTP 401: bad key')).kind,
          AiErrorKind.unauthorized);
      expect(AiErrorMapper.map(Exception('HTTP 429: rate')).kind,
          AiErrorKind.rateLimited);
      expect(AiErrorMapper.map(const FormatException('bad json')).kind,
          AiErrorKind.parseFailed);
      // Never leaks raw exception as the only message for known kinds.
      final m = AiErrorMapper.map(Exception('HTTP 403: secret-body-xyz'));
      expect(m.message.contains('secret-body'), isFalse);
      expect(m.canConfigure, isTrue);
    });
  });

  group('explain prefs → prompt composition', () {
    test('reply language and depth appear in system rules', () {
      const briefEn = AiExplainPrefsSnapshot(
        replyLanguage: AiReplyLanguage.en,
        depth: AiExplainDepth.brief,
        allowRevealAnswer: true,
      );
      final rules = briefEn.toSystemPromptRules();
      expect(rules.contains('English'), isTrue);
      expect(rules.contains('brief'), isTrue);
      expect(rules.toLowerCase(), contains('may reveal'));

      final provider = AiHintProvider(
        engine: _engine(MockClient((_) async => _textResponse('ok'))),
        prefs: AiExplainPrefsStore(
          initial: const AiExplainPrefsSnapshot(
            replyLanguage: AiReplyLanguage.zh,
            depth: AiExplainDepth.detailed,
            injectLearnerContext: true,
          ),
        ),
      );
      provider.setLearnerContext(LearnerAiContext.assemble(
        languageName: 'Turkish',
        weakTerms: const ['merhaba'],
      ));
      final sys = provider.buildSystemPrompt(_ctx());
      expect(sys.contains('detailed'), isTrue);
      expect(sys.contains('[LearnerContext]'), isTrue);
      expect(sys.contains('merhaba'), isTrue);
      expect(sys.toLowerCase(), contains('distractors'));
    });

    test('unsubmitted does not allow reveal when pref off', () {
      final provider = AiHintProvider(
        engine: _engine(MockClient((_) async => _textResponse('ok'))),
        prefs: AiExplainPrefsStore(
          initial: const AiExplainPrefsSnapshot(allowRevealAnswer: false),
        ),
      );
      final sys = provider.buildSystemPrompt(_ctx());
      expect(sys.toLowerCase(), contains('do not directly restate'));
    });

    test('submitted answer enables compare mode', () {
      final provider = AiHintProvider(
        engine: _engine(MockClient((_) async => _textResponse('ok'))),
        prefs: AiExplainPrefsStore(
          initial: const AiExplainPrefsSnapshot(allowRevealAnswer: false),
        ),
      );
      final sys = provider.buildSystemPrompt(_ctx(userAnswer: 'Goodbye'));
      expect(sys.toLowerCase(), contains('submitted'));
    });
  });

  group('genre / report / enrichment fromJson tolerance', () {
    test('DictionaryEnrichment tolerates missing fields', () {
      final e = DictionaryEnrichment.fromJson({}, term: 'merhaba');
      expect(e.term, 'merhaba');
      expect(e.examples, isEmpty);
      expect(e.mnemonic, isEmpty);
      expect(e.toPlainText(), contains('merhaba'));
    });

    test('DiagnosisReport tolerates partial JSON', () {
      final r = DiagnosisReport.fromJson({
        'weakAreas': [
          {'title': 'cases'},
        ],
        'priorityTips': 'not-a-list',
      });
      expect(r.weakAreas.length, 1);
      expect(r.weakAreas.first.title, 'cases');
      expect(r.priorityTips, isEmpty);
      expect(r.toPlainText(), contains('cases'));
    });

    test('depth genres expose toPlainText', () {
      final g = GrammarExplanation.fromJson({
        'explanation': 'x',
        'relatedExamples': ['a'],
      });
      expect(g.toPlainText(), contains('x'));
      final s = SynonymComparison.fromJson({
        'pairs': [
          {
            'a': 'a',
            'b': 'b',
            'nuance': 'n',
            'whenToUseA': '1',
            'whenToUseB': '2',
          }
        ],
      });
      expect(s.toPlainText(), contains('a vs b'));
      final d = SentenceBreakdown.fromJson({
        'tokens': [
          {'surface': 'Ben', 'gloss': 'I', 'role': 'subj'}
        ],
        'structure': 'SV',
      });
      expect(d.toPlainText(), contains('Ben'));
      final w = WhyWrongExplanation.fromJson({
        'whyWrong': 'w',
        'whatYouProbablyThought': 't',
        'howToRemember': 'm',
      });
      expect(w.toPlainText(), contains('w'));
    });
  });

  group('streaming append + cancel + supersede', () {
    test('explainQuestion streams into assistant message', () async {
      final client = MockClient((req) async => _textResponse('考查问候语。'));
      final provider = AiHintProvider(engine: _engine(client));
      await provider.explainQuestion(config: _engineConfig(), ctx: _ctx());
      expect(provider.state, AiHintState.ready);
      expect(provider.latestReply, '考查问候语。');
      expect(provider.messages.length, 2);
      expect(provider.messages.last.role, 'assistant');
    });

    test('cancel keeps partial text and does not apply late content', () async {
      final gate = Completer<void>();
      final client = MockClient((req) async {
        await gate.future;
        return _textResponse('late content that must not appear');
      });
      final provider = AiHintProvider(engine: _engine(client));
      final fut =
          provider.explainQuestion(config: _engineConfig(), ctx: _ctx());
      await Future<void>.delayed(Duration.zero);
      provider.cancel();
      expect(provider.state, AiHintState.idle);
      gate.complete();
      await fut;
      expect(provider.state, AiHintState.idle);
      expect(
        provider.messages.any(
            (m) => m.content.contains('late content that must not appear')),
        isFalse,
      );
    });

    test('superseded explain does not keep stale assistant text', () async {
      final gate = Completer<void>();
      final client = MockClient((req) async {
        if (gate.isCompleted) {
          return _textResponse('B 的讲解。');
        }
        await gate.future;
        return _textResponse('A 的讲解。');
      });
      final provider = AiHintProvider(engine: _engine(client));
      final a = provider.explainQuestion(config: _engineConfig(), ctx: _ctx());
      final b = provider.explainQuestion(
        config: _engineConfig(),
        ctx: const AiQuestionContext(
          language: 'Turkish',
          typeLabel: 'Fill-in-the-blank',
          promptLabel: 'Another',
        ),
      );
      gate.complete();
      await Future.wait([a, b]);
      expect(provider.latestReply, 'B 的讲解。');
      expect(provider.messages.any((m) => m.content.contains('A 的讲解')), isFalse);
    });
  });

  group('tutor chat never uses course JSON path', () {
    test('system prompt forbids course schema', () {
      final p = AiTutorChatProvider(
        engine: _engine(MockClient((_) async => _textResponse('hi'))),
        prefs: AiExplainPrefsStore(),
      );
      final sys = p.buildSystemPromptForTest();
      expect(sys.toLowerCase(), contains('never output course'));
      expect(sys.contains('section/unit/lesson'), isTrue);
      expect(sys.contains('"units"'), isFalse);
    });

    test('ask streams free text only', () async {
      final client = MockClient((req) async => _textResponse('语法讲解。'));
      final p = AiTutorChatProvider(engine: _engine(client));
      await p.ask(config: _engineConfig(), text: '什么是变格？');
      expect(p.state, AiTutorChatState.ready);
      expect(p.messages.last.content, '语法讲解。');
      expect(p.messages.last.role, 'assistant');
    });
  });

  group('dictionary enrichment', () {
    test('parses enrichment via engine JSON path', () async {
      final client = MockClient((req) async => _textResponse(jsonEncode({
            'expandedGloss': 'hello',
            'examples': ['Merhaba!', 'Merhaba, nasılsın?'],
            'mnemonic': 'mer = 早',
          })));
      final p = DictionaryAiProvider(engine: _engine(client));
      final r = await p.enrich(
        config: _engineConfig(),
        language: 'Turkish',
        term: 'merhaba',
      );
      expect(r, isNotNull);
      expect(r!.examples.length, 2);
      expect(r.mnemonic, contains('mer'));
    });
  });

  group('diagnosis rate limit', () {
    test('second generate within interval is rejected', () async {
      final client = MockClient((req) async => _textResponse(jsonEncode({
            'weakAreas': [
              {'title': 'w', 'severity': 'high', 'evidence': []}
            ],
            'priorityTips': ['t'],
            'exampleDrillIdeas': ['d'],
          })));
      final p = AiDiagnosisProvider(
        engine: _engine(client),
        minInterval: const Duration(seconds: 60),
      );
      final ctx = LearnerAiContext.assemble(
        languageName: 'Turkish',
        weakTerms: const ['a'],
      );
      final ok1 =
          await p.generate(config: _engineConfig(), learnerContext: ctx);
      expect(ok1, isTrue);
      expect(p.report, isNotNull);
      final ok2 =
          await p.generate(config: _engineConfig(), learnerContext: ctx);
      expect(ok2, isFalse);
      expect(p.error, 'rate_limited');
    });
  });

  group('saved explanations', () {
    test('save list search delete in memory', () async {
      final store = AiSavedExplanationsStore();
      final id = await store.save(SavedExplanation(
        id: '1',
        title: 'Merhaba',
        body: '问候语',
        source: 'hint',
        createdAt: DateTime(2026, 1, 1),
      ));
      expect(id, '1');
      expect(store.search('问候').length, 1);
      expect(store.search('xyz'), isEmpty);
      await store.delete('1');
      expect(store.items, isEmpty);
    });
  });
}
