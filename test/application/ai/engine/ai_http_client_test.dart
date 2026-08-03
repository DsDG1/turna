// Dart imports:
import 'dart:async';
import 'dart:convert';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/application/ai/engine/ai_provider_preset.dart';

/// A config with a non-DeepSeek preset so the reasoning payload fields are not
/// injected (keeps payload assertions simple).
const AiEngineConfig _config = AiEngineConfig(
  preset: kOpenaiPreset,
  apiKey: 'key',
);

http.Response _chatResponse(String content, {int status = 200}) {
  final body = jsonEncode({
    'choices': [
      {
        'message': {'role': 'assistant', 'content': content},
      },
    ],
    'model': 'gpt-4o',
  });
  return http.Response.bytes(
    utf8.encode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// A client whose response body is driven by a [StreamController] so tests can
/// feed bytes incrementally (for SSE parsing and cancel-mid-stream tests).
class _ControllableClient extends http.BaseClient {
  _ControllableClient(this.controller, this.statusCode);
  final StreamController<List<int>> controller;
  final int statusCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(controller.stream, statusCode);
  }
}

void main() {
  group('AiHttpClient.postJson', () {
    test('returns the parsed body on a 200', () async {
      final client = AiHttpClient.withClient(
        MockClient((_) async => _chatResponse('hello')),
      );
      final body = await client.postJson(
        config: _config,
        model: 'gpt-4o',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      expect(body['choices'], isA<List>());
    });

    test('throws on a non-2xx status', () async {
      final client = AiHttpClient.withClient(
        MockClient((_) async => http.Response('boom', 500)),
      );
      expect(
        () => client.postJson(
          config: _config,
          model: 'gpt-4o',
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('AiHttpClient.postStream SSE', () {
    test('yields one chunk per content fragment then a terminal done chunk',
        () async {
      final controller = StreamController<List<int>>();
      final client =
          AiHttpClient.withClient(_ControllableClient(controller, 200));

      final sse = 'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":" world"}}]}\n\n'
          'data: [DONE]\n\n';
      // Subscribe first (realistic server-streaming order), then feed bytes.
      final fut = client.postStream(
        config: _config,
        model: 'gpt-4o',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      ).toList();
      controller.add(utf8.encode(sse));
      await controller.close();

      final chunks = await fut;
      final deltas = chunks.where((c) => !c.done).map((c) => c.delta).join();
      expect(deltas, 'Hello world');
      expect(chunks.last.done, isTrue);
    });

    test('non-SSE buffered body is emitted as a single chunk', () async {
      // The endpoint ignored `stream: true` and returned a buffered JSON body.
      final controller = StreamController<List<int>>();
      final client =
          AiHttpClient.withClient(_ControllableClient(controller, 200));
      final fut = client.postStream(
        config: _config,
        model: 'gpt-4o',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      ).toList();
      controller.add(utf8.encode(_chatResponse('bulk reply').body));
      await controller.close();

      final chunks = await fut;
      expect(chunks, hasLength(1));
      expect(chunks.single.delta, 'bulk reply');
      expect(chunks.single.done, isTrue);
    });

    test('throws AiCancelled when the cancel token fires mid-stream', () async {
      final controller = StreamController<List<int>>();
      final client =
          AiHttpClient.withClient(_ControllableClient(controller, 200));
      final cancel = AiCancelToken();

      // Drive the stream: emit the first content line, wait for the engine to
      // consume it, then cancel before emitting the second line.
      final fut = client
          .postStream(
            config: _config,
            model: 'gpt-4o',
            messages: const [
              {'role': 'user', 'content': 'hi'},
            ],
            cancelToken: cancel,
          )
          .toList();

      controller.add(
          utf8.encode('data: {"choices":[{"delta":{"content":"first"}}]}\n\n'));
      // Let the stream pump receive the first line.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cancel.cancel();
      // Emit a second line so the loop's moveNext returns and the cancel check
      // at the top of the next iteration fires.
      controller.add(utf8
          .encode('data: {"choices":[{"delta":{"content":"second"}}]}\n\n'));
      await controller.close();

      await expectLater(fut, throwsA(isA<AiCancelled>()));
    });
  });

  group('AiHttpClient json_schema auto-fallback', () {
    test('retries with json_object on a 400 schema rejection', () async {
      var callCount = 0;
      final client = AiHttpClient.withClient(
        MockClient((request) async {
          callCount++;
          if (callCount == 1) {
            // First call used json_schema; provider rejects it.
            return http.Response(
              '{"error":{"message":"response_format unsupported schema"}}',
              400,
            );
          }
          // Retry with json_object succeeds.
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect((body['response_format'] as Map)['type'], 'json_object');
          return _chatResponse('{"ok":true}');
        }),
      );

      final body = await client.postJson(
        config: _config,
        model: 'gpt-4o',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
        responseFormat: const {
          'type': 'json_schema',
          'json_schema': {'name': 's'},
        },
        strict: StrictSchemaMode.auto,
      );

      expect(callCount, 2);
      expect(body['choices'], isA<List>());
      // The probe should remember the rejection for this base URL.
      expect(client.isJsonSchemaKnownUnsupported, isTrue);
    });
  });

  group('AiHttpClient.probeConnection', () {
    test('returns ok=true for a 200 with choices', () async {
      final client = AiHttpClient.withClient(
        MockClient((_) async => _chatResponse('hi')),
      );
      final result = await client.probeConnection(_config);
      expect(result.ok, isTrue);
      expect(result.model, 'gpt-4o');
      expect(result.error, isEmpty);
    });

    test('returns ok=false on an HTTP error', () async {
      final client = AiHttpClient.withClient(
        MockClient((_) async => http.Response('unauthorized', 401)),
      );
      final result = await client.probeConnection(_config);
      expect(result.ok, isFalse);
      expect(result.error, isNotEmpty);
    });
  });

  group('AiHttpClient.postJson reasoning payload', () {
    // The reasoning payload fields (`reasoning_effort` / `thinking`) are only
    // injected when the engine config's `reasoningEnabled` flag is on. That
    // flag combines the preset's `supportsReasoning` with the legacy
    // `isDeepSeekHost(host)` check. These four tests migrated from
    // `ai_course_service_test.dart`'s reasoning group (Phase 2.4 cleanup)
    // pin every branch against the AiHttpClient directly.

    test('omits reasoning fields on a non-DeepSeek host (preset default)',
        () async {
      // kOpenaiPreset has supportsReasoning=false.
      late Map<String, dynamic> sentBody;
      final client = AiHttpClient.withClient(
        MockClient((req) async {
          sentBody = jsonDecode(req.body) as Map<String, dynamic>;
          return _chatResponse('ok');
        }),
      );
      await client.postJson(
        config: _config,
        model: 'gpt-4o',
        messages: const [
          {'role': 'user', 'content': 'hi'}
        ],
        responseFormat: null,
        strict: StrictSchemaMode.off,
      );
      expect(sentBody.containsKey('reasoning_effort'), isFalse);
      expect(sentBody.containsKey('thinking'), isFalse);
    });

    test('includes reasoning fields on a DeepSeek host (preset default)',
        () async {
      late Map<String, dynamic> sentBody;
      final client = AiHttpClient.withClient(
        MockClient((req) async {
          sentBody = jsonDecode(req.body) as Map<String, dynamic>;
          return _chatResponse('ok');
        }),
      );
      // Custom preset + DeepSeek-like baseUrl + supportsReasoningOverride true
      // (mirrors what kDeepseekPreset would yield).
      final config = const AiEngineConfig(
        preset: kCustomPreset,
        apiKey: 'key',
        customBaseUrl: 'https://api.deepseek.com',
        modelChat: 'deepseek-v4-pro',
        modelJson: 'deepseek-v4-pro',
        supportsReasoningOverride: true,
      );
      await client.postJson(
        config: config,
        model: 'deepseek-v4-pro',
        messages: const [
          {'role': 'user', 'content': 'hi'}
        ],
        responseFormat: null,
        strict: StrictSchemaMode.off,
      );
      expect(sentBody['reasoning_effort'], 'high');
      expect(sentBody['thinking'], {'type': 'enabled'});
    });

    test('supportsReasoningOverride=true wins over a non-DeepSeek host',
        () async {
      late Map<String, dynamic> sentBody;
      final client = AiHttpClient.withClient(
        MockClient((req) async {
          sentBody = jsonDecode(req.body) as Map<String, dynamic>;
          return _chatResponse('ok');
        }),
      );
      // OpenAI-like preset with explicit reasoning override on a proxy host.
      final config = const AiEngineConfig(
        preset: kOpenaiPreset,
        apiKey: 'key',
        customBaseUrl: 'https://my-proxy.example.com/v1',
        supportsReasoningOverride: true,
      );
      await client.postJson(
        config: config,
        model: 'some-reasoning-model',
        messages: const [
          {'role': 'user', 'content': 'hi'}
        ],
        responseFormat: null,
        strict: StrictSchemaMode.off,
      );
      expect(sentBody['reasoning_effort'], 'high');
      expect(sentBody['thinking'], {'type': 'enabled'});
    });

    test('supportsReasoningOverride=false suppresses fields on a DeepSeek host',
        () async {
      late Map<String, dynamic> sentBody;
      final client = AiHttpClient.withClient(
        MockClient((req) async {
          sentBody = jsonDecode(req.body) as Map<String, dynamic>;
          return _chatResponse('ok');
        }),
      );
      final config = const AiEngineConfig(
        preset: kCustomPreset,
        apiKey: 'key',
        customBaseUrl: 'https://api.deepseek.com',
        modelChat: 'deepseek-v4-pro',
        modelJson: 'deepseek-v4-pro',
        supportsReasoningOverride: false,
      );
      await client.postJson(
        config: config,
        model: 'deepseek-v4-pro',
        messages: const [
          {'role': 'user', 'content': 'hi'}
        ],
        responseFormat: null,
        strict: StrictSchemaMode.off,
      );
      expect(sentBody.containsKey('reasoning_effort'), isFalse);
      expect(sentBody.containsKey('thinking'), isFalse);
    });
  });
}
