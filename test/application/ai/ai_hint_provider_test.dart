// Dart imports:
import 'dart:async';
import 'dart:convert';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_api_config.dart';
import 'package:varnamala/application/ai/ai_hint_provider.dart';

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

AiApiConfig _config() => const AiApiConfig(
      baseUrl: 'https://example.test/v1',
      apiKey: 'k',
      model: 'm',
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
    final provider = AiHintProvider(client: client);

    await provider.explainQuestion(config: _config(), ctx: _ctx());

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
    final provider = AiHintProvider(client: client);

    await provider.explainQuestion(config: _config(), ctx: _ctx());
    await provider.ask(config: _config(), text: '能再具体点吗？');

    expect(provider.state, AiHintState.ready);
    expect(provider.messages.length, 4);
    expect(provider.messages[1].content, '第一次讲解。');
    expect(provider.messages[2].role, 'user');
    expect(provider.messages[2].content, '能再具体点吗？');
    expect(provider.messages[3].content, '追问回复。');
  });

  test('reset clears history, context and state', () async {
    final client = MockClient((req) async => _textResponse('讲解。'));
    final provider = AiHintProvider(client: client);
    await provider.explainQuestion(config: _config(), ctx: _ctx());
    provider.reset();
    expect(provider.messages, isEmpty);
    expect(provider.context, isNull);
    expect(provider.state, AiHintState.idle);
    expect(provider.latestReply, isNull);
  });

  test('network error sets error state without assistant reply', () async {
    final client = MockClient((req) async => http.Response('boom', 500));
    final provider = AiHintProvider(client: client);

    await provider.explainQuestion(config: _config(), ctx: _ctx());

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
    final provider = AiHintProvider(client: client);

    final a = _ctx();
    final b = const AiQuestionContext(
      language: 'Turkish',
      typeLabel: 'Fill-in-the-blank',
      promptLabel: 'Another question',
    );

    final first = provider.explainQuestion(config: _config(), ctx: a);
    // While A is in flight, start B — this clears messages and bumps the
    // generation token.
    final second = provider.explainQuestion(config: _config(), ctx: b);
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
    final provider = AiHintProvider(client: client);

    final started =
        await provider.ask(config: _config(), text: '能再具体点吗？');

    expect(started, isFalse);
    expect(provider.messages, isEmpty);
    expect(provider.state, AiHintState.idle);
  });

  test('ask returns true and appends when context is present', () async {
    final client = MockClient((req) async => _textResponse('讲解。'));
    final provider = AiHintProvider(client: client);

    await provider.explainQuestion(config: _config(), ctx: _ctx());
    final started =
        await provider.ask(config: _config(), text: '能再具体点吗？');

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
    final provider = AiHintProvider(client: client);

    await provider.explainQuestion(config: _config(), ctx: _ctx());
    // history so far: [user explain, assistant reply]

    final a = provider.ask(config: _config(), text: 'A 的问题');
    final b = provider.ask(config: _config(), text: 'B 的问题');
    gate.complete();
    await Future.wait([a, b]);

    // A's user message must have been cleaned up; only B's user+assistant
    // turn should follow the explain turn.
    expect(provider.messages.any((m) => m.content.contains('A 的问题')), isFalse);
    expect(provider.messages.any((m) => m.content.contains('A 的回复')), isFalse);
    expect(provider.messages.last.role, 'assistant');
    expect(provider.messages.last.content, 'B 的回复。');
  });
}