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
  });

  /// Base URL of an OpenAI-compatible endpoint, e.g.
  /// `https://api.openai.com/v1` or `http://localhost:11434/v1`.
  final String baseUrl;

  /// Secret API key. Never logged or persisted.
  final String apiKey;

  /// Model id, e.g. `gpt-4o-mini`, `deepseek-chat`, `moonshot-v1-8k`.
  final String model;

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  /// Normalized chat-completions URL. Strips any trailing slash on [baseUrl]
  /// and appends `/chat/completions` if the user only provided the base.
  String get chatCompletionsUrl {
    var b = baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (b.endsWith('/chat/completions')) return b;
    return '$b/chat/completions';
  }

  AiApiConfig copyWith({String? baseUrl, String? apiKey, String? model}) =>
      AiApiConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
      );

  @override
  String toString() => 'AiApiConfig(baseUrl: $baseUrl, model: $model)';
}

/// Log a redacted representation (never the key).
void logAiConfig(AiApiConfig c) {
  logger.i('AiApiConfig baseUrl=${c.baseUrl} model=${c.model}');
}