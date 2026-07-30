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
    this.finishReason,
    this.usage,
    this.done = false,
  });

  /// Incremental assistant text for this chunk. May be empty for keep-alive or
  /// usage-only chunks.
  final String delta;

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
