// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_api_config.dart';
import 'package:varnamala/application/ai/ai_course_service.dart';
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
      typeLabel: '单选题',
      promptLabel: 'Merhaba 的意思是？',
      optionsLabel: '你好 / 再见 / 谢谢',
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
}