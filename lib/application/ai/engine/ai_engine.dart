// Dart imports:
import 'dart:async';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_engine_result.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';

/// Single choke point for every LLM call in the app.
///
/// Wraps [AiHttpClient] (network + streaming + cancel + json_schema fallback)
/// and [AiCache] (prompt/response cache), exposing a domain-agnostic API:
///   * [chat] - plain-text reply (alignment / explanation / hint / tutor chat);
///   * [requestJson] - JSON-mode reply (course / lesson / transform / extract);
///   * [probeConnection] - "test connection" probe.
///
/// Domain methods (course generation, lesson transform, knowledge extraction,
/// etc.) stay on `AiCourseService` and the feature providers - they build
/// prompts with `ai_prompt_builder.dart` and parse results with their own
/// domain parsers, delegating only the HTTP + cache + stream + cancel hop to
/// this engine. This keeps the engine free of course-schema knowledge and
/// avoids a circular dependency between the engine and the service shim.
///
/// Caching: when `config.cacheEnabled` is on, the engine consults [AiCache]
/// before the network. A cache hit returns immediately; for streaming callers
/// the cached content is delivered to `onChunk` as a single fragment. The cache
/// key is `sha256(model | messages | responseFormat)` and never includes the
/// API key (see [AiCache.makeKey]).
@lazySingleton
class AiEngine {
  AiEngine(this._http, this._cache);

  final AiHttpClient _http;
  final AiCache _cache;

  /// Plain-text chat. [messages] must already include the system prompt if
  /// needed. Uses the chat-side model (`config.selectModel('chat')`) and no
  /// JSON response format.
  ///
  /// When [onChunk] is supplied the call streams and each content fragment is
  /// forwarded as it arrives; otherwise the call is non-streaming. [cancelToken]
  /// aborts a streaming call mid-flight (throws [AiCancelled] into the stream).
  Future<AiEngineResult> chat({
    required AiEngineConfig config,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.5,
    void Function(String delta)? onChunk,
    AiCancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return _callOnce(
      config: config,
      model: config.selectModel('chat'),
      messages: messages,
      temperature: temperature,
      responseFormat: null,
      strict: StrictSchemaMode.off,
      onChunk: onChunk,
      cancelToken: cancelToken,
      timeout: timeout,
    );
  }

  /// JSON-mode call. Uses the JSON-side model (`config.selectModel('json')`)
  /// and a response format resolved from [config.strictSchema] (plus the
  /// optional [jsonSchema]). The returned [AiEngineResult.content] is the raw
  /// JSON string from the model; the caller parses it with its domain parser.
  Future<AiEngineResult> requestJson({
    required AiEngineConfig config,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.4,
    Map<String, dynamic>? jsonSchema,
    void Function(String delta)? onChunk,
    AiCancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 120),
  }) {
    final responseFormat = _http.resolveResponseFormat(
      config: config,
      strict: config.strictSchema,
      jsonSchema: jsonSchema,
    );
    return _callOnce(
      config: config,
      model: config.selectModel('json'),
      messages: messages,
      temperature: temperature,
      responseFormat: responseFormat,
      strict: config.strictSchema,
      onChunk: onChunk,
      cancelToken: cancelToken,
      timeout: timeout,
    );
  }

  /// Minimal endpoint probe - delegates to [AiHttpClient.probeConnection].
  Future<({bool ok, String error, String model, int latencyMs})> probeConnection(
    AiEngineConfig config, {
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _http.probeConnection(config, timeout: timeout);

  AiCacheStats cacheStats() => _cache.stats();

  /// Drop both memory and disk cache entries (the "clear cache" button).
  void clearCache() => _cache.clearAll();

  /// Attach the on-disk cache mirror. Called once on startup by the app shell
  /// with the app documents directory; a no-op on web.
  void attachDiskCache(String dir) => _cache.enableDiskMirror(dir);

  /// The single low-level primitive. Checks the cache, otherwise dispatches to
  /// [AiHttpClient.postJson] (non-streaming) or [AiHttpClient.postStream]
  /// (streaming), then writes the body back to the cache.
  Future<AiEngineResult> _callOnce({
    required AiEngineConfig config,
    required String model,
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required Map<String, dynamic>? responseFormat,
    required StrictSchemaMode strict,
    required void Function(String delta)? onChunk,
    required AiCancelToken? cancelToken,
    required Duration timeout,
  }) async {
    if (!config.isComplete) {
      throw Exception(
          'AI config incomplete: please fill in Base URL / API Key / Model.');
    }

    final key =
        AiCache.makeKey(model, messages, responseFormat);

    // Cache lookup (only when caching is enabled at both the config and cache
    // level). A hit short-circuits the network entirely.
    if (config.cacheEnabled && _cache.enabled) {
      final cached = _cache.get(key);
      if (cached != null) {
        final content = _extractAssistantText(cached);
        if (onChunk != null && content.isNotEmpty) {
          // Deliver the cached content as a single fragment so streaming UIs
          // still render something (mirrors `read_streaming` non-SSE fallback).
          onChunk(content);
        }
        return AiEngineResult(
          content: content,
          body: cached,
          cacheHit: true,
          usage: _extractUsage(cached),
        );
      }
    }

    if (onChunk != null) {
      // Streaming path: forward deltas, accumulate, cache the synthetic body.
      final fragments = <String>[];
      Map<String, int>? usage;
      await for (final chunk in _http.postStream(
        config: config,
        model: model,
        messages: messages,
        temperature: temperature,
        responseFormat: responseFormat,
        strict: strict,
        cancelToken: cancelToken,
        timeout: timeout,
      )) {
        if (chunk.done) {
          if (chunk.usage != null) usage = chunk.usage;
          // Some endpoints send the full content only in the terminal chunk
          // (non-SSE fallback). Prefer accumulated fragments; fall back to the
          // terminal delta when nothing accumulated.
          if (fragments.isEmpty && chunk.delta.isNotEmpty) {
            fragments.add(chunk.delta);
            onChunk(chunk.delta);
          }
          break;
        }
        if (chunk.delta.isNotEmpty) {
          fragments.add(chunk.delta);
          onChunk(chunk.delta);
        }
        if (chunk.usage != null) usage = chunk.usage;
      }
      final content = fragments.join();
      final body = _synthesizeStreamedBody(content, usage, model);
      if (config.cacheEnabled && _cache.enabled) {
        _cache.put(key, body);
      }
      return AiEngineResult(
        content: content,
        body: body,
        cacheHit: false,
        usage: usage,
      );
    }

    // Non-streaming path.
    final body = await _http.postJson(
      config: config,
      model: model,
      messages: messages,
      temperature: temperature,
      responseFormat: responseFormat,
      strict: strict,
      cancelToken: cancelToken,
      timeout: timeout,
    );
    final content = _extractAssistantText(body);
    if (config.cacheEnabled && _cache.enabled) {
      _cache.put(key, body);
    }
    return AiEngineResult(
      content: content,
      body: body,
      cacheHit: false,
      usage: _extractUsage(body),
    );
  }

  /// Extract the assistant's reply text from an OpenAI-compatible completion
  /// body. Mirrors `AiCourseService.extractAssistantText` (kept here so the
  /// engine doesn't depend on the service shim and create a cycle).
  String _extractAssistantText(Map<String, dynamic> body) {
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final first = choices.first;
    if (first is! Map) return '';
    final message = first['message'];
    if (message is! Map) return '';
    final content = message['content'];
    if (content is! String) return '';
    return content.trim();
  }

  Map<String, int>? _extractUsage(Map<String, dynamic> body) {
    final usage = body['usage'];
    if (usage is Map) {
      try {
        return usage.cast<String, int>();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Build a non-streaming-shaped body from a streamed response so the cache
  /// stores a uniform shape and downstream parsers (which expect
  /// `choices[0].message.content`) work on both paths. Mirrors
  /// `ai/client.py:read_streaming`'s terminal `json.dumps`.
  Map<String, dynamic> _synthesizeStreamedBody(
      String content, Map<String, int>? usage, String model) {
    return {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content},
          'finish_reason': 'stop',
        },
      ],
      'usage': usage ?? const <String, int>{},
      'model': model,
    };
  }
}
