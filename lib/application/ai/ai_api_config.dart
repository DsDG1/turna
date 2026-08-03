/// True when [baseUrl]'s host points at DeepSeek. DeepSeek's
/// `/chat/completions` endpoint accepts the `reasoning_effort` / `thinking`
/// payload fields (returned reasoning lives in a separate `reasoning_content`
/// field and never leaks into `message.content`); other OpenAI-compatible
/// endpoints (OpenAI, Ollama, Moonshot) reject or error on unknown fields.
///
/// This is the single host-detection predicate for the Dart side — the
/// engine's `reasoningEnabled` defaults to it. The Python tool GUI mirrors it
/// as `AiApiConfig.is_deepseek`.
///
/// Phase 2.4: the legacy `AiApiConfig` class is gone (no remaining
/// constructor call sites). Only this host predicate is kept.
bool isDeepSeekHost(String baseUrl) {
  final host = Uri.tryParse(baseUrl)?.host ?? '';
  return host == 'api.deepseek.com' || host.endsWith('.deepseek.com');
}
