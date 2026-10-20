/// A single fragment emitted while streaming an OpenAI-compatible
/// `/chat/completions` response.
///
/// Mirrors the per-line parse output of `tool/gui/src/backend/ai_stream.py`
/// (`parse_sse_line` / `parse_sse_usage`). The Dart HTTP client assembles a
/// stream of these from the raw SSE lines so consumers (chat pages, the depth
/// tutor sheet) can render tokens as they arrive.
class AiStreamChunk {
  const AiStreamChunk({
    required this.delta,
    this.reasoningDelta,
    this.finishReason,
    this.usage,
    this.done = false,
  });

  /// Incremental assistant text for this chunk. May be empty for keep-alive or
  /// usage-only chunks.
  final String delta;

  /// Incremental *reasoning* text for this chunk (DeepSeek / MiMo emit the
  /// chain of thought under `delta.reasoning_content`).
  ///
  /// Kept separate from [delta] on purpose: reasoning is not part of the
  /// answer, so it must never be appended to the assistant message or fed to a
  /// JSON parser. Consumers use it only to prove the model is working during
  /// the otherwise silent thinking phase.
  final String? reasoningDelta;

  /// `finish_reason` from the terminal chunk (`stop`, `length`, ...), or null
  /// when the chunk is not the last one.
  final String? finishReason;

  /// Terminal usage block (`prompt_tokens` / `completion_tokens` /
  /// `total_tokens`) when the endpoint appends one before `[DONE]`.
  final Map<String, int>? usage;

  /// `true` for the synthetic terminal chunk the client emits after the stream
  /// closes (or after a cache hit delivered as a single chunk).
  final bool done;
}
