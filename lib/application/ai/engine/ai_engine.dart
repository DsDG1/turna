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
import 'package:turna/application/ai/engine/ai_usage_meter.dart';
import 'package:turna/core/performance_trace.dart';

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
/// key is `sha256(model | sampling | messages | response_format)` where
/// `sampling` carries temperature / reasoning / max tokens, and never includes
/// the API key (see [AiCache.makeKey]).
@lazySingleton
class AiEngine {
  AiEngine(this._http, this._cache, {AiUsageMeter? meter})
      : _meter = meter ?? AiUsageMeter.instance;

  final AiHttpClient _http;
  final AiCache _cache;
  final AiUsageMeter _meter;

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
    int? maxTokens,
    void Function(String delta)? onChunk,
    AiCancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return _callOnce(
      config: config,
      model: config.selectModel('chat'),
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
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
  ///
  /// [jsonSchema] must be a full `json_schema` envelope (`{name, strict,
  /// schema}`); see `ai_json_schemas.dart` for the shared ones. Without it,
  /// `strictSchema` can never escalate past `json_object`.
  Future<AiEngineResult> requestJson({
    required AiEngineConfig config,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.4,
    int? maxTokens,
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
      maxTokens: maxTokens,
      responseFormat: responseFormat,
      strict: config.strictSchema,
      onChunk: onChunk,
      cancelToken: cancelToken,
      timeout: timeout,
    );
  }

  /// Minimal endpoint probe - delegates to [AiHttpClient.probeConnection].
  Future<({bool ok, String error, String model, int latencyMs})>
      probeConnection(
    AiEngineConfig config, {
    Duration timeout = const Duration(seconds: 10),
  }) =>
          _http.probeConnection(config, timeout: timeout);

  AiCacheStats cacheStats() => _cache.stats();

  /// Session token counters (see [AiUsageMeter]).
  AiUsageSnapshot usageStats() => _meter.snapshot();

  /// Drop all process-local AI response cache entries.
  void clearCache() => _cache.clear();

  /// Forget the per-Base-URL `json_schema` capability verdicts.
  ///
  /// The probe is keyed by Base URL only, so a config change (provider switch,
  /// edited Base URL) must not inherit a verdict recorded against a different
  /// endpoint. Called by `AiEngineConfigHolder.updateConfig`.
  void resetCapabilityProbes() => _http.resetCapabilityProbes();

  /// The single low-level primitive. Checks the cache, otherwise dispatches to
  /// [AiHttpClient.postJson] (non-streaming) or [AiHttpClient.postStream]
  /// (streaming), then writes the body back to the cache.
  Future<AiEngineResult> _callOnce({
    required AiEngineConfig config,
    required String model,
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required int? maxTokens,
    required Map<String, dynamic>? responseFormat,
    required StrictSchemaMode strict,
    required void Function(String delta)? onChunk,
    required AiCancelToken? cancelToken,
    required Duration timeout,
  }) async {
    final trace = Stopwatch()..start();
    var notificationCount = 0;
    var firstChunkRecorded = false;
    void Function(String)? tracedChunk;
    if (onChunk != null) {
      tracedChunk = (delta) {
        notificationCount++;
        if (!firstChunkRecorded && delta.isNotEmpty) {
          firstChunkRecorded = true;
          PerformanceTrace.instance.record(
            feature: 'ai',
            operation: 'firstChunk',
            duration: trace.elapsed,
            resultSize: 1,
          );
        }
        onChunk(delta);
      };
    }
    try {
      final result = await _callOnceUntraced(
        config: config,
        model: model,
        messages: messages,
        temperature: temperature,
        maxTokens: maxTokens,
        responseFormat: responseFormat,
        strict: strict,
        onChunk: tracedChunk,
        cancelToken: cancelToken,
        timeout: timeout,
      );
      trace.stop();
      _meter.recordSuccess(usage: result.usage, cacheHit: result.cacheHit);
      PerformanceTrace.instance.record(
        feature: 'ai',
        operation: 'ask',
        duration: trace.elapsed,
        // Count characters on the non-streaming path and chunks on the
        // streaming one: they measure different things, so the tracer labels
        // the unit rather than letting two incomparable numbers share a field.
        resultSize: onChunk == null ? result.content.length : notificationCount,
        cacheStatus:
            result.cacheHit ? TraceCacheStatus.hit : TraceCacheStatus.miss,
      );
      return result;
    } on AiCancelled {
      trace.stop();
      _meter.recordFailure(cancelled: true);
      PerformanceTrace.instance.record(
        feature: 'ai',
        operation: 'ask',
        duration: trace.elapsed,
        resultSize: notificationCount,
        outcome: TraceOutcome.cancelled,
      );
      rethrow;
    } catch (_) {
      trace.stop();
      _meter.recordFailure(cancelled: false);
      PerformanceTrace.instance.record(
        feature: 'ai',
        operation: 'ask',
        duration: trace.elapsed,
        resultSize: notificationCount,
        outcome: TraceOutcome.error,
      );
      rethrow;
    }
  }

  Future<AiEngineResult> _callOnceUntraced({
    required AiEngineConfig config,
    required String model,
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required int? maxTokens,
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

    // Fields that change the answer but live outside `messages` /
    // `response_format` must be part of the digest, otherwise a user who
    // changes the temperature (or toggles reasoning) keeps being served the
    // reply generated under the old settings.
    final sampling = 't=$temperature|r=${config.reasoningEnabled}'
        '|m=${maxTokens ?? 0}';

    // Large payloads canonicalise + hash off the main isolate (small ones
    // hash inline — see AiCache.makeKeyAsync).
    final key = await AiCache.makeKeyAsync(
      model,
      messages,
      responseFormat,
      sampling: sampling,
    );

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
          finishReason: _extractFinishReason(cached),
        );
      }
    }

    if (onChunk != null) {
      // Streaming path: forward deltas, accumulate, cache the synthetic body.
      final fragments = <String>[];
      final reasoning = StringBuffer();
      Map<String, int>? usage;
      String? finishReason;
      await for (final chunk in _http.postStream(
        config: config,
        model: model,
        messages: messages,
        temperature: temperature,
        responseFormat: responseFormat,
        maxTokens: maxTokens,
        strict: strict,
        cancelToken: cancelToken,
        timeout: timeout,
      )) {
        if (chunk.reasoningDelta != null && chunk.reasoningDelta!.isNotEmpty) {
          // Chain of thought: recorded for diagnostics, never delivered as
          // assistant text (it is not the answer and would poison parsers).
          reasoning.write(chunk.reasoningDelta);
        }
        if (chunk.done) {
          if (chunk.usage != null) usage = chunk.usage;
          if (chunk.finishReason != null) finishReason = chunk.finishReason;
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
        if (chunk.finishReason != null) finishReason = chunk.finishReason;
      }
      final content = fragments.join();
      final body =
          _synthesizeStreamedBody(content, usage, model, finishReason);
      if (config.cacheEnabled && _cache.enabled) {
        _cache.put(key, body);
      }
      return AiEngineResult(
        content: content,
        body: body,
        cacheHit: false,
        usage: usage,
        finishReason: finishReason,
        reasoningText: reasoning.isEmpty ? null : reasoning.toString(),
      );
    }

    // Non-streaming path.
    final body = await _http.postJson(
      config: config,
      model: model,
      messages: messages,
      temperature: temperature,
      responseFormat: responseFormat,
      maxTokens: maxTokens,
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
      finishReason: _extractFinishReason(body),
      reasoningText: _extractReasoningText(body),
    );
  }

  /// Extract the assistant's reply text from an OpenAI-compatible completion
  /// body. Mirrors `AiCourseService.extractAssistantText` (kept here so the
  /// engine doesn't depend on the service shim and create a cycle).
  String _extractAssistantText(Map<String, dynamic> body) {
    final message = _firstMessage(body);
    if (message == null) return '';
    final content = message['content'];
    if (content is! String) return '';
    return content.trim();
  }

  /// Chain-of-thought text on a non-streaming reply, when the endpoint returns
  /// it alongside the answer.
  String? _extractReasoningText(Map<String, dynamic> body) {
    final message = _firstMessage(body);
    if (message == null) return null;
    final raw = message['reasoning_content'] ?? message['reasoning'];
    if (raw is! String || raw.trim().isEmpty) return null;
    return raw;
  }

  Map? _firstMessage(Map<String, dynamic> body) {
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is! Map) return null;
    return message;
  }

  /// `choices[0].finish_reason`, or `null` when the endpoint omitted it.
  String? _extractFinishReason(Map<String, dynamic> body) {
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final reason = first['finish_reason'];
    if (reason is! String || reason.isEmpty) return null;
    return reason;
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
  ///
  /// [finishReason] is preserved rather than hard-coded to `stop`: a stream cut
  /// off by the token limit must stay identifiable as `length`, both for the
  /// caller and for anything later read back out of the cache.
  Map<String, dynamic> _synthesizeStreamedBody(
    String content,
    Map<String, int>? usage,
    String model,
    String? finishReason,
  ) {
    return {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content},
          'finish_reason': finishReason ?? 'stop',
        },
      ],
      'usage': usage ?? const <String, int>{},
      'model': model,
    };
  }
}
