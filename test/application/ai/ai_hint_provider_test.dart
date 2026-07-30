// Dart imports:
import 'dart:async';
import 'dart:convert';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_hint_provider.dart';
import 'package:varnamala/application/ai/engine/ai_cache.dart';
import 'package:varnamala/application/ai/engine/ai_engine.dart';
import 'package:varnamala/application/ai/engine/ai_engine_config.dart';
import 'package:varnamala/application/ai/engine/ai_http_client.dart';
import 'package:varnamala/application/ai/engine/ai_provider_preset.dart';

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

/// A complete engine config whose effective Base URL is
/// `https://example.test/v1` (custom preset carries the URL as customBaseUrl),
/// matching the legacy test config. Caching is disabled so every call reaches
/// the injected mock client.
AiEngineConfig _engineConfig() => const AiEngineConfig(
      preset: kCustomPreset,
      apiKey: 'k',
      modelChat: 'm',
      modelJson: 'm',
      customBaseUrl: 'https://example.test/v1',
      cacheEnabled: false,
    );

/// Build a provider backed by [client] through a real [AiEngine] (cache
/// disabled). Mirrors how the shim path used the mock client, so the existing
/// gating / request-body assertions keep working.
AiHintProvider _provider(http.Client client) => AiHintProvider(
      engine: AiEngine(
        AiHttpClient.withClient(client),
        AiCache.forTest(maxEntries: 0, enabled: false),
      ),
    );

AiQuestionContext _ctx() => const AiQuestionContext(
      language: 'Turkish',
      typeLabel: 'Multiple Choice',
      promptLabel: 'What does Merhaba mean?',
      optionsLabel: 'Hello / Goodbye / Thanks',
    );

void main() {
  test('explainQuestion appends assistant reply and ends in ready', () async {
    final client = MockClient((req) async => _textResponse('考查问候语。'));
    final provider = _provider(client);

    await provider.explainQuestion(config: _engineConfig(), ctx: _ctx());

    expect(provider.state, AiHintState.ready);
    expect(provider.error, isNull);
    // user turn + assistant turn.
    expect(provider.messages.length, 2);
    expect(provider.messages.first.role, 'user');
    expect(provider.messages.last.role, 'assistant');
    expect(provider.messages.last.content, '考查问候语。');
    expect(provider.latestReply, '考查问候语。');
    expect(provider.context, isNotNull);
  });

  test('ask appends a follow-up exchange preserving history', () async {
    var call = 0;
    final client = MockClient((req) async {
      call++;
      return _textResponse(call == 1 ? '第一次讲解。' : '追问回复。');
    });
    final provider = _provider(client);

    await provider.explainQuestion(config: _engineConfig(), ctx: _ctx());
    await provider.ask(config: _engineConfig(), text: '能再具体点吗？');

    expect(provider.state, AiHintState.ready);
    expect(provider.messages.length, 4);
    expect(provider.messages[1].content, '第一次讲解。');
    expect(provider.messages[2].role, 'user');
    expect(provider.messages[2].content, '能再具体点吗？');
    expect(provider.messages[3].content, '追问回复。');
  });

  test('reset clears history, context and state', () async {
    final client = MockClient((req) async => _textResponse('讲解。'));
    final provider = _provider(client);
    await provider.explainQuestion(config: _engineConfig(), ctx: _ctx());
    provider.reset();
    expect(provider.messages, isEmpty);
    expect(provider.context, isNull);
    expect(provider.state, AiHintState.idle);
    expect(provider.latestReply, isNull);
  });

  test('network error sets error state without assistant reply', () async {
    final client = MockClient((req) async => http.Response('boom', 500));
    final provider = _provider(client);

    await provider.explainQuestion(config: _engineConfig(), ctx: _ctx());

    expect(provider.state, AiHintState.error);
    expect(provider.error, isNotNull);
    // user turn was added, no assistant turn.
    expect(provider.messages.length, 1);
    expect(provider.latestReply, isNull);
  });

  test('a stale in-flight explainQuestion does not append into a newer '
      'conversation after reset', () async {
    final gate = Completer<void>();
    final client = MockClient((req) async {
      // First request (question A) waits on the gate so we can interleave
      // a reset + new question before it resolves.
      if (gate.isCompleted) {
        return _textResponse('B 的讲解。');
      }
      await gate.future;
      return _textResponse('A 的讲解。');
    });
    final provider = _provider(client);

    final a = _ctx();
    final b = const AiQuestionContext(
      language: 'Turkish',
      typeLabel: 'Fill-in-the-blank',
      promptLabel: 'Another question',
    );

    final first = provider.explainQuestion(config: _engineConfig(), ctx: a);
    // While A is in flight, start B - this clears messages and bumps the
    // generation token (and cancels A's token).
    final second = provider.explainQuestion(config: _engineConfig(), ctx: b);
    // Let A's network call resolve.
    gate.complete();
    await Future.wait([first, second]);

    // A's reply must NOT have been appended; only B's user + assistant turn
    // should be present.
    expect(provider.state, AiHintState.ready);
    expect(provider.messages.length, 2);
    expect(provider.messages.last.content, 'B 的讲解。');
    expect(provider.messages.any((m) => m.content.contains('A 的讲解')), isFalse);
  });

  test('ask returns false (no-op) when context is null', () async {
    final client = MockClient((req) async => _textResponse('回复。'));
    final provider = _provider(client);

    final started =
        await provider.ask(config: _engineConfig(), text: '能再具体点吗？');

    expect(started, isFalse);
    expect(provider.messages, isEmpty);
    expect(provider.state, AiHintState.idle);
  });

  test('ask returns true and appends when context is present', () async {
    final client = MockClient((req) async => _textResponse('讲解。'));
    final provider = _provider(client);

    await provider.explainQuestion(config: _engineConfig(), ctx: _ctx());
    final started =
        await provider.ask(config: _engineConfig(), text: '能再具体点吗？');

    expect(started, isTrue);
    expect(provider.messages.last.role, 'assistant');
  });

  test('a superseded ask removes its orphan user message', () async {
    // Two asks race: A is in flight when B starts. A must drop its assistant
    // reply AND clean up the orphan user message it appended, so the
    // transcript isn't left with a 'user asked, AI never answered' gap.
    final gate = Completer<void>();
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      final lastContent =
          (messages.last as Map)['content'] as String? ?? '';
      // Gate only A's follow-up so explainQuestion and B can resolve.
      if (lastContent.contains('A 的问题')) {
        await gate.future;
        return _textResponse('A 的回复。');
      }
      return _textResponse('B 的回复。');
    });
    final provider = _provider(client);

    await provider.explainQuestion(config: _engineConfig(), ctx: _ctx());
    // history so far: [user explain, assistant reply]

    final a = provider.ask(config: _engineConfig(), text: 'A 的问题');
    final b = provider.ask(config: _engineConfig(), text: 'B 的问题');
    gate.complete();
    await Future.wait([a, b]);

    // A's user message must have been cleaned up; only B's user+assistant
    // turn should follow the explain turn.
    expect(provider.messages.any((m) => m.content.contains('A 的问题')), isFalse);
    expect(provider.messages.any((m) => m.content.contains('A 的回复')), isFalse);
    expect(provider.messages.last.role, 'assistant');
    expect(provider.messages.last.content, 'B 的回复。');
  });

  test('cancel aborts an in-flight explainQuestion and returns to idle', () async {
    final gate = Completer<void>();
    final client = MockClient((req) async {
      await gate.future;
      return _textResponse('never seen。');
    });
    final provider = _provider(client);

    // Start a generation that hangs on the gate, then cancel it.
    final future = provider.explainQuestion(config: _engineConfig(), ctx: _ctx());
    // Let the request reach the mock (awaiting the gate) before cancelling.
    await Future<void>.delayed(Duration.zero);
    provider.cancel();
    expect(provider.state, AiHintState.idle);

    // Releasing the gate lets the cancelled call settle; it must not append a
    // reply or flip to ready/error.
    gate.complete();
    await future;
    expect(provider.state, AiHintState.idle);
    expect(provider.latestReply, isNull);
    // Only the user turn was added; no assistant turn.
    expect(provider.messages.length, 1);
  });

  // ─── Depth-tutor genres ──────────────────────────────────────────────
  // Each genre fakes the engine via the mock client returning the genre JSON
  // as the chat content, then asserts the typed parse.

  test('explainGrammarPoint parses a typed grammar explanation', () async {
    final client = MockClient((req) async => _textResponse(
        '{"explanation":"主语+谓语","relatedExamples":["Ben giderim."],"contrastWith":["-iyor"]}'));
    final provider = _provider(client);

    final r = await provider.explainGrammarPoint(
      config: _engineConfig(),
      language: 'Turkish',
      sentence: 'Ben giderim.',
      grammarPoint: 'simple present',
    );

    expect(r.explanation, '主语+谓语');
    expect(r.relatedExamples, ['Ben giderim.']);
    expect(r.contrastWith, ['-iyor']);
  });

  test('compareSynonyms parses pairwise nuance entries', () async {
    final client = MockClient((req) async => _textResponse(
        '{"pairs":[{"a":"bilmek","b":"tanımak","nuance":"知道 vs 认识","whenToUseA":"事实","whenToUseB":"人","examples":["Onu tanıyorum."]}]}'));
    final provider = _provider(client);

    final r = await provider.compareSynonyms(
      config: _engineConfig(),
      language: 'Turkish',
      words: const ['bilmek', 'tanımak'],
    );

    expect(r.pairs.length, 1);
    expect(r.pairs.first.a, 'bilmek');
    expect(r.pairs.first.b, 'tanımak');
    expect(r.pairs.first.examples, ['Onu tanıyorum.']);
  });

  test('decomposeSentence parses tokens and structure', () async {
    final client = MockClient((req) async => _textResponse(
        '{"tokens":[{"surface":"Ben","lemma":"ben","gloss":"我","role":"主语"},{"surface":"giderim","lemma":"gitmek","gloss":"我去","role":"谓语"}],"structure":"主谓句"}'));
    final provider = _provider(client);

    final r = await provider.decomposeSentence(
      config: _engineConfig(),
      language: 'Turkish',
      sentence: 'Ben giderim.',
    );

    expect(r.tokens.length, 2);
    expect(r.tokens.first.surface, 'Ben');
    expect(r.tokens.first.gloss, '我');
    expect(r.tokens.last.lemma, 'gitmek');
    expect(r.structure, '主谓句');
  });

  test('explainWhyWrong parses the three-field explanation', () async {
    final client = MockClient((req) async => _textResponse(
        '{"whyWrong":"大小写错误","whatYouProbablyThought":"以为是小写","howToRemember":"句首大写"}'));
    final provider = _provider(client);

    final r = await provider.explainWhyWrong(
      config: _engineConfig(),
      language: 'Turkish',
      userAnswer: 'merhaba',
      correctAnswer: 'Merhaba',
      questionContext: 'Greet someone',
    );

    expect(r.whyWrong, '大小写错误');
    expect(r.whatYouProbablyThought, '以为是小写');
    expect(r.howToRemember, '句首大写');
  });

  test('genre methods tolerate a markdown-fenced JSON reply', () async {
    final client = MockClient((req) async => _textResponse(
        '```json\n{"explanation":"x","relatedExamples":[],"contrastWith":[]}\n```'));
    final provider = _provider(client);

    final r = await provider.explainGrammarPoint(
      config: _engineConfig(),
      language: 'Turkish',
      sentence: 's',
      grammarPoint: 'g',
    );

    expect(r.explanation, 'x');
    expect(r.relatedExamples, isEmpty);
  });
}
