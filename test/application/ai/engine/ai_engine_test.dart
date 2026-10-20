// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/application/ai/engine/ai_provider_preset.dart';

const AiEngineConfig _config = AiEngineConfig(
  preset: kMimoPreset,
  apiKey: 'key',
);

http.Response _reply(String content) {
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

void main() {
  group('AiEngine.chat cache', () {
    test('returns cacheHit=false on a cold call and warms the cache', () async {
      var callCount = 0;
      final engine = AiEngine(
        AiHttpClient.withClient(
          MockClient((_) async {
            callCount++;
            return _reply('hello');
          }),
        ),
        AiCache.forTest(maxEntries: 4),
      );

      final r1 = await engine.chat(
        config: _config,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      expect(r1.cacheHit, isFalse);
      expect(r1.content, 'hello');
      expect(callCount, 1);

      // Second identical call should hit the cache (no extra network call).
      final r2 = await engine.chat(
        config: _config,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      expect(r2.cacheHit, isTrue);
      expect(r2.content, 'hello');
      expect(callCount, 1);
    });

    test('forwards cached content to onChunk as a single fragment', () async {
      var callCount = 0;
      final engine = AiEngine(
        AiHttpClient.withClient(
          MockClient((_) async {
            callCount++;
            return _reply('streamed');
          }),
        ),
        AiCache.forTest(maxEntries: 4),
      );

      // Warm the cache (non-streaming).
      await engine.chat(
        config: _config,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );

      // Replay with onChunk; the cache hit should deliver the content as one
      // fragment without a network call.
      final deltas = <String>[];
      final r = await engine.chat(
        config: _config,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
        onChunk: deltas.add,
      );
      expect(r.cacheHit, isTrue);
      expect(deltas, ['streamed']);
      expect(callCount, 1);
    });

    test('cache disabled at config skips the cache', () async {
      var callCount = 0;
      final engine = AiEngine(
        AiHttpClient.withClient(
          MockClient((_) async {
            callCount++;
            return _reply('hello');
          }),
        ),
        AiCache.forTest(maxEntries: 4),
      );
      const noCacheConfig = AiEngineConfig(
        preset: kMimoPreset,
        apiKey: 'key',
        cacheEnabled: false,
      );

      await engine.chat(
        config: noCacheConfig,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      await engine.chat(
        config: noCacheConfig,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      expect(callCount, 2); // both hit the network
    });
  });

  // 回归：JSON 请求必须带着真实模型 id 上线。`custom` 预设 + 空着的 JSON 模型
  // 曾把 `model: ""` 发出去，服务端回 `invalid params, unknown model ''`，
  // 现场表现是「AI 对话能用，学习诊断 / 定制复习 / 生成课程全挂」。
  group('AiEngine.requestJson model resolution', () {
    test('a blank JSON model is sent as the chat model, never as ""', () async {
      String? sentModel;
      final engine = AiEngine(
        AiHttpClient.withClient(
          MockClient((request) async {
            final decoded = jsonDecode(request.body) as Map<String, dynamic>;
            sentModel = decoded['model'] as String?;
            return _reply('{}');
          }),
        ),
        AiCache.forTest(maxEntries: 4),
      );
      const config = AiEngineConfig(
        preset: kCustomPreset,
        apiKey: 'key',
        customBaseUrl: 'https://api.minimax.cn/v1',
        modelChat: 'MiniMax-M3.1-Flash',
        modelJson: '',
      );

      await engine.requestJson(
        config: config,
        messages: const [
          {'role': 'user', 'content': 'plan'},
        ],
      );

      expect(sentModel, 'MiniMax-M3.1-Flash');
    });
  });

  group('AiEngine.clearCache', () {
    test('drops entries so the next call is a miss', () async {
      var callCount = 0;
      final engine = AiEngine(
        AiHttpClient.withClient(
          MockClient((_) async {
            callCount++;
            return _reply('hello');
          }),
        ),
        AiCache.forTest(maxEntries: 4),
      );
      await engine.chat(
        config: _config,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      engine.clearCache();
      await engine.chat(
        config: _config,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      expect(callCount, 2);
    });
  });
}
