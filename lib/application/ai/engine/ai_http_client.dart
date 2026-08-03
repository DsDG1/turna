// Dart imports:
import 'dart:async';
import 'dart:convert';

// Package imports:
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_stream_chunk.dart';

/// OpenAI-compatible HTTP client with streaming, cooperative cancel, and
/// `json_schema` -> `json_object` auto-fallback.
///
/// Ported from `tool/gui/src/backend/ai/client.py` (`request_chat`,
/// `read_streaming`, `verify_connection`, `looks_like_json_schema_rejection`).
///
/// Single network entry for the engine. Non-streaming callers use [postJson];
/// streaming callers use [postStream] and consume [AiStreamChunk]s. The
/// `json_schema` auto-fallback fires only when the caller hands a
/// `response_format: {type: json_schema, ...}` and the endpoint returns HTTP 400
/// with a schema-rejection marker; it then retries once with `json_object` and
/// remembers the probe per Base URL so subsequent calls skip the probe.
@lazySingleton
class AiHttpClient {
  AiHttpClient() : _client = http.Client();

  /// Test-only constructor that injects a mock [http.Client] (matches the
  /// `MockClient` style in `test/application/ai/ai_course_service_test.dart`).
  AiHttpClient.withClient(http.Client client) : _client = client;

  final http.Client _client;

  /// Process-local capability probe: Base URL -> accepts `json_schema`?
  /// Mirrors `ai/config.py:AiApiConfig._json_schema_supported`, but lifted to
  /// the client so it survives `AiEngineConfig` being rebuilt (the config is a
  /// const value object).
  final Map<String, bool> _jsonSchemaProbe = {};

  /// Mark that [baseUrl] rejected `json_schema` (auto-fallback).
  void markJsonSchemaUnsupported(String baseUrl) =>
      _jsonSchemaProbe[baseUrl] = false;

  /// Mark that [baseUrl] accepted `json_schema`.
  void markJsonSchemaSupported(String baseUrl) =>
      _jsonSchemaProbe[baseUrl] = true;

  /// `true` when any probed Base URL is known to reject `json_schema`. Exposed
  /// for tests and for the Settings sheet to hint at the active fallback.
  bool get isJsonSchemaKnownUnsupported =>
      _jsonSchemaProbe.values.any((v) => v == false);

  /// Resolve a `strictSchema` policy to the response-format map to actually
  /// send. Returns `null` for plain-text chat (no JSON mode).
  ///
  /// - [StrictSchemaMode.off]: always `json_object`.
  /// - [StrictSchemaMode.on]: `json_schema` (caller-supplied [jsonSchema]) or
  ///   `json_object` when no schema is supplied.
  /// - [StrictSchemaMode.auto]: same as `on`, but if the probe says the endpoint
  ///   rejects `json_schema`, downgrade to `json_object` without a round-trip.
  Map<String, dynamic>? resolveResponseFormat({
    required AiEngineConfig config,
    required StrictSchemaMode strict,
    Map<String, dynamic>? jsonSchema,
  }) {
    if (strict == StrictSchemaMode.off) return {'type': 'json_object'};
    if (jsonSchema == null) return {'type': 'json_object'};
    if (strict == StrictSchemaMode.auto &&
        _jsonSchemaProbe[config.baseUrl] == false) {
      return {'type': 'json_object'};
    }
    return {
      'type': 'json_schema',
      'json_schema': jsonSchema,
    };
  }

  /// Build the chat-completions payload (without `stream` unless requested).
  Map<String, dynamic> buildPayload({
    required AiEngineConfig config,
    required String model,
    required List<Map<String, dynamic>> messages,
    required double temperature,
    Map<String, dynamic>? responseFormat,
    int? maxTokens,
    bool stream = false,
  }) {
    final payload = <String, dynamic>{
      'model': model,
      'messages': messages,
      'temperature': temperature,
    };
    if (maxTokens != null) payload['max_tokens'] = maxTokens;
    if (config.reasoningEnabled) {
      payload['reasoning_effort'] = 'high';
      payload['thinking'] = const {'type': 'enabled'};
    }
    if (responseFormat != null) payload['response_format'] = responseFormat;
    if (stream) payload['stream'] = true;
    return payload;
  }

  http.Request _buildRequest(
      AiEngineConfig config, Map<String, dynamic> payload) {
    final req = http.Request('POST', Uri.parse(config.chatCompletionsUrl));
    req.headers['Content-Type'] = 'application/json';
    req.headers['Authorization'] = 'Bearer ${config.apiKey}';
    // Disable transparent gzip so streamed SSE lines are plain text we can
    // split by line (mirrors `ai/client.py` `Accept-Encoding: identity`).
    req.headers['Accept-Encoding'] = 'identity';
    req.body = jsonEncode(payload);
    return req;
  }

  /// Send the request, applying the `json_schema` -> `json_object` auto-fallback
  /// on a 400 schema-rejection. Returns the [http.StreamedResponse] for the
  /// caller to consume (buffered or streamed). Throws [Exception] on network /
  /// HTTP errors and [AiCancelled] if [cancelToken] fires during the fallback's
  /// error-body drain.
  Future<http.StreamedResponse> _send({
    required AiEngineConfig config,
    required Map<String, dynamic> payload,
    required StrictSchemaMode strict,
    AiCancelToken? cancelToken,
  }) async {
    if (!config.isComplete) {
      throw Exception(
          'AI config incomplete: please fill in Base URL / API Key / Model.');
    }
    final res = await _client.send(_buildRequest(config, payload));

    final rf = payload['response_format'];
    final isJsonSchema = rf is Map && rf['type'] == 'json_schema';
    if (res.statusCode == 400 &&
        isJsonSchema &&
        strict == StrictSchemaMode.auto) {
      final detail = await _readBody(res, cancelToken: cancelToken);
      if (_looksLikeJsonSchemaRejection(detail)) {
        markJsonSchemaUnsupported(config.baseUrl);
        final retryPayload = Map<String, dynamic>.from(payload);
        retryPayload['response_format'] = {'type': 'json_object'};
        return _client.send(_buildRequest(config, retryPayload));
      }
      // 400 that isn't a schema rejection - surface it.
      throw Exception('HTTP 400: ${_truncate(detail)}');
    }
    return res;
  }

  /// Non-streaming POST. Returns the parsed response body. Polls [cancelToken]
  /// between body chunks (mirrors `ai/client.py`'s 65536-byte cancel poll).
  Future<Map<String, dynamic>> postJson({
    required AiEngineConfig config,
    required String model,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.7,
    Map<String, dynamic>? responseFormat,
    int? maxTokens,
    StrictSchemaMode strict = StrictSchemaMode.off,
    AiCancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final payload = buildPayload(
      config: config,
      model: model,
      messages: messages,
      temperature: temperature,
      responseFormat: responseFormat,
      maxTokens: maxTokens,
    );
    final res = await _send(
      config: config,
      payload: payload,
      strict: strict,
      cancelToken: cancelToken,
    ).timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final detail = await _readBody(res, cancelToken: cancelToken);
      throw Exception('HTTP ${res.statusCode}: ${_truncate(detail)}');
    }
    final body = await _readBody(res, cancelToken: cancelToken);
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Could not parse AI response: $e');
    }
  }

  /// Streaming POST. Yields [AiStreamChunk]s as content fragments arrive, with
  /// a terminal `done: true` chunk carrying the usage block when the endpoint
  /// emits one. Polls [cancelToken] between lines and throws [AiCancelled] into
  /// the stream on cancel (mirrors `ai_stream.py:iter_sse`).
  ///
  /// If the endpoint ignores `stream: true` and returns a buffered JSON body,
  /// the whole content is emitted as a single chunk (mirrors `read_streaming`'s
  /// non-SSE fallback).
  Stream<AiStreamChunk> postStream({
    required AiEngineConfig config,
    required String model,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.7,
    Map<String, dynamic>? responseFormat,
    StrictSchemaMode strict = StrictSchemaMode.off,
    AiCancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 120),
  }) {
    // Drive a StreamController from a plain async function rather than using
    // `async*` + `StreamIterator` (that combination deadlocks under the test
    // harness and is fragile with single-subscription response streams). The
    // controller is closed in `_runPostStream`'s `finally`.
    // ignore: close_sinks
    final out = StreamController<AiStreamChunk>();
    _runPostStream(
      out: out,
      config: config,
      model: model,
      messages: messages,
      temperature: temperature,
      responseFormat: responseFormat,
      strict: strict,
      cancelToken: cancelToken,
      timeout: timeout,
    );
    return out.stream;
  }

  Future<void> _runPostStream({
    required StreamController<AiStreamChunk> out,
    required AiEngineConfig config,
    required String model,
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required Map<String, dynamic>? responseFormat,
    required StrictSchemaMode strict,
    required AiCancelToken? cancelToken,
    required Duration timeout,
  }) async {
    try {
      final payload = buildPayload(
        config: config,
        model: model,
        messages: messages,
        temperature: temperature,
        responseFormat: responseFormat,
        stream: true,
      );
      final res = await _send(
        config: config,
        payload: payload,
        strict: strict,
        cancelToken: cancelToken,
      ).timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final detail = await _readBody(res, cancelToken: cancelToken);
        throw Exception('HTTP ${res.statusCode}: ${_truncate(detail)}');
      }

      final lineStream =
          res.stream.transform(utf8.decoder).transform(const LineSplitter());

      Map<String, int>? usage;
      var sawSse = false;
      // Buffer non-data lines until we know whether this is an SSE stream or a
      // buffered JSON body (the endpoint ignored `stream: true`).
      final rawBuf = StringBuffer();

      await for (final line in lineStream) {
        if (cancelToken != null && cancelToken.isCanceled) {
          throw const AiCancelled();
        }
        if (!line.trimLeft().startsWith('data:')) {
          if (!sawSse) rawBuf.writeln(line);
          continue;
        }
        if (!sawSse) {
          sawSse = true;
          rawBuf.clear();
        }
        final p = _parseSseLine(line);
        if (p.usage != null) usage = p.usage;
        if (p.content != null && p.content!.isNotEmpty) {
          out.add(AiStreamChunk(delta: p.content!));
        }
        if (p.done) {
          out.add(AiStreamChunk(
              delta: '', usage: usage, finishReason: 'stop', done: true));
          return;
        }
      }

      if (!sawSse) {
        // Non-SSE fallback: parse the buffered body as a normal completion.
        final content = _extractBufferedContent(rawBuf.toString());
        out.add(AiStreamChunk(delta: content, finishReason: 'stop', done: true));
        return;
      }
      // Stream ended without an explicit `[DONE]` sentinel.
      out.add(AiStreamChunk(
          delta: '', usage: usage, finishReason: 'stop', done: true));
    } catch (e) {
      out.addError(e);
    } finally {
      await out.close();
    }
  }

  /// Minimal endpoint probe used by the "test connection" button. Mirrors
  /// `ai/client.py:verify_connection`. Returns `{ok, error, model, latencyMs}`.
  Future<({bool ok, String error, String model, int latencyMs})>
      probeConnection(
    AiEngineConfig config, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final sw = Stopwatch()..start();
    try {
      final body = await postJson(
        config: config,
        model: config.selectModel('chat'),
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
        temperature: 0,
        maxTokens: 1,
        strict: StrictSchemaMode.off,
        timeout: timeout,
      );
      sw.stop();
      final choices = body['choices'];
      final model = (body['model'] ?? '').toString();
      if (choices is! List || choices.isEmpty) {
        return (
          ok: false,
          error: 'API returned empty choices',
          model: model,
          latencyMs: sw.elapsedMilliseconds
        );
      }
      return (
        ok: true,
        error: '',
        model: model,
        latencyMs: sw.elapsedMilliseconds
      );
    } catch (e) {
      sw.stop();
      return (ok: false, error: e.toString(), model: '', latencyMs: sw.elapsedMilliseconds);
    }
  }

  // --- helpers ---------------------------------------------------------

  /// Parse a single SSE line. Mirrors `ai_stream.py:parse_sse_line` +
  /// `parse_sse_usage` combined into one pass. Returns the content fragment
  /// (if any), a usage block (if the line carries one), and a `done` flag for
  /// the terminal `[DONE]` sentinel.
  ({String? content, Map<String, int>? usage, bool done}) _parseSseLine(
      String line) {
    if (!line.trimLeft().startsWith('data:')) {
      return (content: null, usage: null, done: false);
    }
    final payloadStr = line.trimLeft().substring(5).trim();
    if (payloadStr == '[DONE]') return (content: null, usage: null, done: true);
    if (payloadStr.isEmpty) return (content: null, usage: null, done: false);
    final obj = _tryParseJson(payloadStr);
    if (obj == null) return (content: null, usage: null, done: false);

    Map<String, int>? usage;
    final chunkUsage = obj['usage'];
    if (chunkUsage is Map) {
      usage = chunkUsage.cast<String, int>();
    }

    String? content;
    final choices = obj['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final delta = first['delta'];
        if (delta is Map) {
          final c = delta['content'];
          if (c is String) content = c;
        }
      }
    }
    return (content: content, usage: usage, done: false);
  }

  Future<String> _readBody(http.StreamedResponse res,
      {AiCancelToken? cancelToken}) async {
    final buf = <int>[];
    await for (final chunk in res.stream) {
      if (cancelToken != null && cancelToken.isCanceled) {
        throw const AiCancelled();
      }
      buf.addAll(chunk);
    }
    return utf8.decode(buf, allowMalformed: true);
  }

  Map<String, dynamic>? _tryParseJson(String s) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  /// Extract `choices[0].message.content` from a buffered (non-SSE) JSON body.
  String _extractBufferedContent(String body) {
    final obj = _tryParseJson(body);
    if (obj == null) return body;
    final choices = obj['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map) {
          final content = message['content'];
          if (content is String) return content;
        }
      }
    }
    return '';
  }

  /// Heuristic: does this HTTP 400 body indicate the provider rejected
  /// `response_format.type == "json_schema"`? Mirrors
  /// `ai/client.py:looks_like_json_schema_rejection`.
  bool _looksLikeJsonSchemaRejection(String detail) {
    final lowered = detail.toLowerCase();
    return const ['schema', 'response_format', 'unsupported', 'unknown field']
        .any((m) => lowered.contains(m));
  }

  String _truncate(String s, [int n = 300]) =>
      s.length <= n ? s : '${s.substring(0, n)}…';
}
