// Project imports:
import 'package:varnamala/core/logger.dart';

/// In-memory only configuration for an OpenAI-compatible chat completions
/// endpoint. The fields are deliberately **not persisted** — they live in the
/// provider for the current session and are discarded on app exit.
class AiApiConfig {
  const AiApiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.supportsReasoning,
  });

  /// Base URL of an OpenAI-compatible endpoint, e.g.
  /// `https://api.deepseek.com` or `http://localhost:11434/v1`.
  final String baseUrl;

  /// Secret API key. Never logged or persisted.
  final String apiKey;

  /// Model id, e.g. `deepseek-v4-pro`, `deepseek-v4-flash`, `moonshot-v1-8k`.
  final String model;

  /// Whether the endpoint accepts the `reasoning_effort` / `thinking` payload
  /// fields used for guided reasoning. `null` (the default) infers this from
  /// [baseUrl] via [isDeepSeekHost] — DeepSeek's documented behavior — so the
  /// common case needs no extra config. Set it explicitly to override the
  /// inference for a reasoning-capable endpoint on a non-DeepSeek host (e.g. a
  /// self-hosted reasoning model behind a proxy) or to suppress it for a
  /// DeepSeek-host endpoint that should not use reasoning.
  final bool? supportsReasoning;

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  /// True when [supportsReasoning] should be treated as on. Falls back to
  /// [isDeepSeekHost] of [baseUrl] when [supportsReasoning] was left null.
  bool get reasoningEnabled => supportsReasoning ?? isDeepSeekHost(baseUrl);

  /// Normalized chat-completions URL. Strips any trailing slash on [baseUrl]
  /// and appends `/chat/completions` if the user only provided the base.
  String get chatCompletionsUrl {
    var b = baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (b.endsWith('/chat/completions')) return b;
    return '$b/chat/completions';
  }

  AiApiConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? supportsReasoning,
  }) =>
      AiApiConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        supportsReasoning: supportsReasoning ?? this.supportsReasoning,
      );

  @override
  String toString() => 'AiApiConfig(baseUrl: $baseUrl, model: $model)';
}

/// True when [baseUrl]'s host points at DeepSeek. DeepSeek's
/// `/chat/completions` endpoint accepts the `reasoning_effort` / `thinking`
/// payload fields (returned reasoning lives in a separate `reasoning_content`
/// field and never leaks into `message.content`); other OpenAI-compatible
/// endpoints (OpenAI, Ollama, Moonshot) reject or error on unknown fields.
///
/// This is the single host-detection predicate for the Dart side —
/// [AiApiConfig.reasoningEnabled] defaults to it, and any other caller that
/// needs to gate DeepSeek-specific behavior should call this rather than
/// re-deriving the host match. The Python tool GUI mirrors it as
/// `AiApiConfig.is_deepseek`.
bool isDeepSeekHost(String baseUrl) {
  final host = Uri.tryParse(baseUrl)?.host ?? '';
  return host == 'api.deepseek.com' || host.endsWith('.deepseek.com');
}

/// Convenience: whether this config's endpoint points at DeepSeek.
bool isDeepSeekConfig(AiApiConfig config) => isDeepSeekHost(config.baseUrl);

/// Log a redacted representation (never the key).
void logAiConfig(AiApiConfig c) {
  logger.i('AiApiConfig baseUrl=${c.baseUrl} model=${c.model}');
}