// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_stream_chunk.dart';

/// The endpoint answered with a 3xx redirect and the request was not
/// followed.
///
/// Every request this client builds carries `Authorization: Bearer <key>`. A
/// redirect is an instruction to move that request — and the header with it —
/// somewhere the user never typed, so it is refused rather than followed: the
/// destination's own origin policy decides whether the credential would have
/// survived, and a user-configured endpoint should not get to choose. The
/// response body is intentionally not surfaced, because a body from an
/// unwanted destination is a new place a secret could be echoed from.
class AiRedirectNotFollowed implements Exception {
  const AiRedirectNotFollowed(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'AI endpoint redirected (HTTP $statusCode)';
}

/// A non-2xx answer from the endpoint, carrying the status code so callers can
/// classify it without string-matching.
///
/// [detail] is already truncated and secret-redacted: it is the only part of
/// the server body that is ever allowed downstream (logs, error copy, the
/// transparency report). Classification happens on [statusCode]; the text is
/// for humans only.
class AiHttpError implements Exception {
  const AiHttpError({required this.statusCode, required this.detail});

  final int statusCode;
  final String detail;

  /// Worth retrying on the same request: rate limiting and transient upstream
  /// failures. 4xx client errors (auth / model / bad request) are excluded —
  /// retrying those burns quota without changing the outcome.
  bool get isRetryable =>
      statusCode == 408 ||
      statusCode == 425 ||
      statusCode == 429 ||
      (statusCode >= 500 && statusCode <= 599);

  @override
  String toString() =>
      detail.isEmpty ? 'HTTP $statusCode' : 'HTTP $statusCode: $detail';
}

/// OpenAI-compatible HTTP client with streaming, cooperative cancel,
/// `json_schema` -> `json_object` auto-fallback, and bounded retries.
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

  /// How many times one logical request may hit the wire: the first attempt
  /// plus `maxAttempts - 1` retries.
  static const int maxAttempts = 3;

  static const Duration _retryBaseDelay = Duration(milliseconds: 700);
  static const Duration _maxRetryDelay = Duration(seconds: 8);

  /// Idle ceiling while reading a **buffered** body, measured between network
  /// chunks (not as a total). An endpoint that stops sending mid-body used to
  /// hang the caller forever; 90 s is far longer than any legitimate pause, so
  /// this only ever fires on a genuinely dead connection.
  static const Duration bodyIdleTimeout = Duration(seconds: 90);

  /// Idle ceiling while reading an **SSE** stream. Shorter than
  /// [bodyIdleTimeout] because a healthy stream emits a delta (or a keep-alive
  /// line) every few seconds.
  static const Duration streamIdleTimeout = Duration(seconds: 45);

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

  /// Forget every capability probe.
  ///
  /// The probe is keyed by Base URL only, so switching provider or editing the
  /// Base URL must not inherit a verdict recorded against a different endpoint.
  /// Called by `AiEngineConfigHolder` whenever the config changes.
  void resetCapabilityProbes() => _jsonSchemaProbe.clear();

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
    // Never follow a redirect. This request carries `Authorization: Bearer
    // <key>`; whether that header survives a cross-host hop is up to each
    // platform HTTP stack's own cross-origin scrubbing, so a user-configured
    // endpoint answering 30x to somewhere else would decide where the key
    // goes. Mirrors `webdav_client.dart`, which states the same rule for the
    // same reason ("credentials must not leak to another host").
    req.followRedirects = false;
    req.body = jsonEncode(payload);
    return req;
  }

  /// Send one logical request, retrying transient failures.
  ///
  /// Retries wrap the **response-head** stage only: the body has not been read
  /// yet, so a retry can never duplicate streamed text. Timeouts are *not*
  /// retried — a request that did not answer within its budget will not answer
  /// sooner on a second attempt, and stacking budgets would keep the UI
  /// spinning for minutes.
  Future<http.StreamedResponse> _send({
    required AiEngineConfig config,
    required Map<String, dynamic> payload,
    required StrictSchemaMode strict,
    AiCancelToken? cancelToken,
    required Duration timeout,
  }) async {
    if (!config.isComplete) {
      throw Exception(
          'AI config incomplete: please fill in Base URL / API Key / Model.');
    }
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final res = await _sendOnce(
          config: config,
          payload: payload,
          strict: strict,
          cancelToken: cancelToken,
        ).timeout(timeout);

        if (attempt < maxAttempts && _isRetryableStatus(res.statusCode)) {
          final hint = _retryAfterOf(res);
          await _discardBody(res);
          await _awaitRetry(attempt, hint, cancelToken);
          continue;
        }
        return res;
      } on AiRedirectNotFollowed {
        rethrow;
      } on AiHttpError {
        rethrow;
      } on AiCancelled {
        rethrow;
      } on TimeoutException {
        rethrow;
      } catch (e) {
        if (attempt >= maxAttempts || !_isRetryableError(e)) rethrow;
        await _awaitRetry(attempt, null, cancelToken);
      }
    }
  }

  /// One wire attempt: send, refuse redirects, apply the schema fallback.
  Future<http.StreamedResponse> _sendOnce({
    required AiEngineConfig config,
    required Map<String, dynamic> payload,
    required StrictSchemaMode strict,
    AiCancelToken? cancelToken,
  }) async {
    final res =
        await _sendChecked(_client.send(_buildRequest(config, payload)));

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
        return _sendChecked(_client.send(_buildRequest(config, retryPayload)));
      }
      // 400 that isn't a schema rejection - surface it.
      throw AiHttpError(statusCode: 400, detail: _redact(detail));
    }
    return res;
  }

  /// Reject a 3xx instead of handing it to the caller as a normal response.
  ///
  /// Covers every send path, including the `json_schema` retry, so a redirect
  /// cannot slip through on the second attempt.
  Future<http.StreamedResponse> _sendChecked(
      Future<http.StreamedResponse> pending) async {
    final res = await pending;
    if (res.statusCode >= 300 && res.statusCode < 400) {
      await _discardBody(res);
      throw AiRedirectNotFollowed(res.statusCode);
    }
    return res;
  }

  /// Drain an unwanted response body so the connection can be reused.
  Future<void> _discardBody(http.StreamedResponse res) async {
    try {
      await res.stream.drain<void>();
    } catch (_) {
      // Best-effort hygiene only: the body of a refused redirect is of no
      // interest, and failing to drain it must not mask the refusal.
    }
  }

  static bool _isRetryableStatus(int status) =>
      status == 408 ||
      status == 425 ||
      status == 429 ||
      (status >= 500 && status <= 599);

  /// Only transport-level failures are retryable: the request either never
  /// reached the endpoint or the connection dropped mid-handshake.
  static bool _isRetryableError(Object error) =>
      error is SocketException ||
      error is HttpException ||
      error is http.ClientException;

  /// `Retry-After` in seconds, clamped to [_maxRetryDelay]. Some gateways send
  /// a HTTP-date instead; that is ignored rather than guessed at.
  Duration? _retryAfterOf(http.StreamedResponse res) {
    final raw = res.headers['retry-after'];
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds == null || seconds <= 0) return null;
    final parsed = Duration(seconds: seconds);
    return parsed > _maxRetryDelay ? _maxRetryDelay : parsed;
  }

  Future<void> _awaitRetry(
    int attempt,
    Duration? serverHint,
    AiCancelToken? cancelToken,
  ) async {
    if (cancelToken != null && cancelToken.isCanceled) {
      throw const AiCancelled();
    }
    final backoff = _retryBaseDelay * (1 << (attempt - 1));
    final raw = serverHint ?? backoff;
    await Future<void>.delayed(raw > _maxRetryDelay ? _maxRetryDelay : raw);
    if (cancelToken != null && cancelToken.isCanceled) {
      throw const AiCancelled();
    }
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
      timeout: timeout,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final detail = await _readBody(res, cancelToken: cancelToken);
      throw AiHttpError(
        statusCode: res.statusCode,
        detail: _redact(detail),
      );
    }
    final body = await _readBody(res, cancelToken: cancelToken);
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Could not parse AI response: $e');
    }
  }

  /// Streaming POST. Yields [AiStreamChunk]s as content fragments arrive, with
  /// a terminal `done: true` chunk carrying the usage block and the real
  /// `finish_reason` when the endpoint emits one. Polls [cancelToken] between
  /// lines and throws [AiCancelled] into the stream on cancel (mirrors
  /// `ai_stream.py:iter_sse`).
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
    int? maxTokens,
    StrictSchemaMode strict = StrictSchemaMode.off,
    AiCancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 120),
  }) {
    // Drive a StreamController from a plain async function rather than using
    // `async*` + `StreamIterator` (that combination deadlocks under the test
    // harness and is fragile with single-subscription response streams). The
    // controller is closed in `_runPostStream`'s `finally`.
    //
    // `onCancel` matters beyond hygiene: when a page is disposed mid-stream the
    // subscription goes away but the SSE body keeps arriving. Without the
    // abort flag the client would keep reading a response nobody can see.
    var aborted = false;
    // ignore: close_sinks
    final out = StreamController<AiStreamChunk>(
      onCancel: () {
        aborted = true;
      },
    );
    _runPostStream(
      out: out,
      config: config,
      model: model,
      messages: messages,
      temperature: temperature,
      responseFormat: responseFormat,
      maxTokens: maxTokens,
      strict: strict,
      cancelToken: cancelToken,
      timeout: timeout,
      isAborted: () => aborted,
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
    required int? maxTokens,
    required StrictSchemaMode strict,
    required AiCancelToken? cancelToken,
    required Duration timeout,
    required bool Function() isAborted,
  }) async {
    try {
      final payload = buildPayload(
        config: config,
        model: model,
        messages: messages,
        temperature: temperature,
        responseFormat: responseFormat,
        maxTokens: maxTokens,
        stream: true,
      );
      final res = await _send(
        config: config,
        payload: payload,
        strict: strict,
        cancelToken: cancelToken,
        timeout: timeout,
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final detail = await _readBody(res, cancelToken: cancelToken);
        throw AiHttpError(
          statusCode: res.statusCode,
          detail: _redact(detail),
        );
      }

      // `.timeout` on the *decoded* line stream is an idle detector: a healthy
      // SSE connection emits an event every few seconds, so silence for
      // [streamIdleTimeout] means the connection is dead. Without it a stalled
      // upstream left the UI on "generating…" forever.
      final lineStream = res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(streamIdleTimeout);

      Map<String, int>? usage;
      String? finishReason;
      var sawSse = false;
      // Buffer non-data lines until we know whether this is an SSE stream or a
      // buffered JSON body (the endpoint ignored `stream: true`).
      final rawBuf = StringBuffer();

      await for (final line in lineStream) {
        if (isAborted()) return;
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
        if (p.finishReason != null) finishReason = p.finishReason;
        if (p.reasoning != null && p.reasoning!.isNotEmpty) {
          out.add(AiStreamChunk(delta: '', reasoningDelta: p.reasoning));
        }
        if (p.content != null && p.content!.isNotEmpty) {
          out.add(AiStreamChunk(delta: p.content!));
        }
        if (p.done) {
          out.add(AiStreamChunk(
            delta: '',
            usage: usage,
            finishReason: finishReason ?? 'stop',
            done: true,
          ));
          return;
        }
      }

      if (!sawSse) {
        // Non-SSE fallback: parse the buffered body as a normal completion.
        final buffered = _tryParseJson(rawBuf.toString());
        final content = _extractBufferedContent(rawBuf.toString());
        final bufferedReason =
            buffered == null ? null : _firstChoiceField(buffered, 'finish_reason');
        out.add(AiStreamChunk(
          delta: content,
          finishReason: bufferedReason is String ? bufferedReason : 'stop',
          done: true,
        ));
        return;
      }
      // Stream ended without an explicit `[DONE]` sentinel.
      out.add(AiStreamChunk(
        delta: '',
        usage: usage,
        finishReason: finishReason ?? 'stop',
        done: true,
      ));
    } catch (e) {
      out.addError(e);
    } finally {
      await out.close();
    }
  }

  /// Minimal endpoint probe used by the "test connection" button. Mirrors
  /// `ai/client.py:verify_connection`. Returns `{ok, error, model, latencyMs}`.
  ///
  /// Reasoning fields are stripped for the probe: it only has to prove that
  /// the endpoint, key and model id are valid, and a model in thinking mode can
  /// burn the entire one-token budget before emitting any `content` — which
  /// made a perfectly working endpoint report as broken.
  Future<({bool ok, String error, String model, int latencyMs})>
      probeConnection(
    AiEngineConfig config, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final sw = Stopwatch()..start();
    final probeConfig = config.reasoningEnabled
        ? config.copyWith(supportsReasoningOverride: false)
        : config;
    try {
      final body = await postJson(
        config: probeConfig,
        model: probeConfig.selectModel('chat'),
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
      return (
        ok: false,
        error: e.toString(),
        model: '',
        latencyMs: sw.elapsedMilliseconds
      );
    }
  }

  // --- helpers ---------------------------------------------------------

  /// Parse a single SSE line. Mirrors `ai_stream.py:parse_sse_line` +
  /// `parse_sse_usage` combined into one pass. Returns the content fragment,
  /// the reasoning fragment (if any), a usage block (if the line carries one),
  /// the `finish_reason` when this line is terminal, and a `done` flag for the
  /// `[DONE]` sentinel.
  ({
    String? content,
    String? reasoning,
    Map<String, int>? usage,
    String? finishReason,
    bool done
  }) _parseSseLine(String line) {
    if (!line.trimLeft().startsWith('data:')) {
      return (
        content: null,
        reasoning: null,
        usage: null,
        finishReason: null,
        done: false
      );
    }
    final payloadStr = line.trimLeft().substring(5).trim();
    if (payloadStr == '[DONE]') {
      return (
        content: null,
        reasoning: null,
        usage: null,
        finishReason: null,
        done: true
      );
    }
    if (payloadStr.isEmpty) {
      return (
        content: null,
        reasoning: null,
        usage: null,
        finishReason: null,
        done: false
      );
    }
    final obj = _tryParseJson(payloadStr);
    if (obj == null) {
      return (
        content: null,
        reasoning: null,
        usage: null,
        finishReason: null,
        done: false
      );
    }

    Map<String, int>? usage;
    final chunkUsage = obj['usage'];
    if (chunkUsage is Map) {
      usage = chunkUsage.cast<String, int>();
    }

    String? content;
    String? reasoning;
    String? finishReason;
    final choices = obj['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final fr = first['finish_reason'];
        if (fr is String && fr.isNotEmpty) finishReason = fr;
        final delta = first['delta'];
        if (delta is Map) {
          final c = delta['content'];
          if (c is String) content = c;
          // DeepSeek / MiMo put the chain of thought here. It is deliberately
          // NOT merged into `content` — it is not the answer and would poison
          // every JSON parser downstream.
          final r = delta['reasoning_content'] ?? delta['reasoning'];
          if (r is String) reasoning = r;
        }
      }
    }
    return (
      content: content,
      reasoning: reasoning,
      usage: usage,
      finishReason: finishReason,
      done: false
    );
  }

  Object? _firstChoiceField(Map<String, dynamic> obj, String field) {
    final choices = obj['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) return first[field];
    }
    return null;
  }

  Future<String> _readBody(http.StreamedResponse res,
      {AiCancelToken? cancelToken}) async {
    final buf = <int>[];
    // Idle ceiling, not a total ceiling: a slow-but-alive body is allowed to
    // take as long as it needs, while a connection that goes silent forever is
    // cut. `.timeout` on the stream fires on the gap between events.
    await for (final chunk in res.stream.timeout(bodyIdleTimeout)) {
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
    } catch (_) {/* non-JSON body — return null below */}
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

  /// How many characters of an upstream error body are ever kept.
  static const int _maxDetailChars = 200;

  /// Strip credential-looking tokens out of an upstream body before it can
  /// reach a log, an error banner or the exportable transparency report.
  ///
  /// Some gateways echo the offending header back ("Incorrect API key provided:
  /// sk-abc...xyz"), so truncating alone is not enough.
  String _redact(String s) {
    var text = s.replaceAllMapped(
      RegExp(r'(sk-|ak-|Bearer\s+)[A-Za-z0-9_\-*.=]{4,}'),
      (Match m) => '${m.group(1)}***',
    );
    text = text.replaceAllMapped(
      RegExp(r'("?(?:api[_-]?key|authorization)"?\s*[:=]\s*"?)[^"\s,}]{4,}',
          caseSensitive: false),
      (Match m) => '${m.group(1)}***',
    );
    return _truncate(text);
  }

  String _truncate(String s, [int n = _maxDetailChars]) =>
      s.length <= n ? s : '${s.substring(0, n)}…';
}
