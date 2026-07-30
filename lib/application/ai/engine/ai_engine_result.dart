/// Outcome of a single [AiEngine] call.
///
/// Carries the assistant's reply text ([content]), the raw decoded completion
/// body ([body], used as the cache value and for usage extraction), whether the
/// result was served from cache ([cacheHit]), and the optional token [usage]
/// block reported by the endpoint.
class AiEngineResult {
  const AiEngineResult({
    required this.content,
    this.body,
    this.cacheHit = false,
    this.usage,
  });

  /// Assistant reply text. For JSON-mode calls this is the JSON string the
  /// model returned; the caller parses it with its domain parser.
  final String content;

  /// Raw decoded chat-completion body (`{choices, usage, model, ...}`), or the
  /// synthetic body assembled from a streamed response. This is what the cache
  /// stores and what [usage] is read from.
  final Map<String, dynamic>? body;

  /// `true` when the result was served from the response cache (no network
  /// call). Streaming callers still receive the cached content via `onChunk`
  /// as a single fragment.
  final bool cacheHit;

  /// Terminal usage block (`prompt_tokens` / `completion_tokens` /
  /// `total_tokens`) when the endpoint reported one.
  final Map<String, int>? usage;
}
