/// Outcome of a single [AiEngine] call.
///
/// Carries the assistant's reply text ([content]), the raw decoded completion
/// body ([body], used as the cache value and for usage extraction), whether the
/// result was served from cache ([cacheHit]), the token [usage] block reported
/// by the endpoint, and the terminal [finishReason].
class AiEngineResult {
  const AiEngineResult({
    required this.content,
    this.body,
    this.cacheHit = false,
    this.usage,
    this.finishReason,
    this.reasoningText,
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

  /// Why generation stopped: `stop`, `length`, `content_filter`, … `null` when
  /// the endpoint did not report one.
  ///
  /// This field exists because `length` is the difference between "the model
  /// wrote bad JSON" and "the reply was cut off before the closing brace".
  /// Without it a truncated course/practice body surfaced as a parse failure
  /// and the user was told to retry something that could never succeed.
  final String? finishReason;

  /// Accumulated chain-of-thought text when the endpoint streamed one
  /// (`delta.reasoning_content`). Never part of [content].
  final String? reasoningText;

  /// `true` when the model was cut off by the output token limit.
  bool get isTruncated => finishReason == 'length';
}
