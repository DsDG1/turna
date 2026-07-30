// Project imports:
import 'package:varnamala/application/ai/ai_api_config.dart';
import 'package:varnamala/application/ai/engine/ai_provider_preset.dart';

/// Strict-JSON response-format policy. Mirrors `ai/config.py:AiApiConfig.strict_schema`.
///
/// - [auto]: try `json_schema`; if the provider rejects it (HTTP 400 / "schema"
///   family), fall back to `json_object` and remember the probe for the process.
/// - [on]: force `json_schema` and surface any rejection as an error.
/// - [off]: force `json_object` (the loosest JSON mode).
enum StrictSchemaMode { auto, on, off }

/// Unified, in-memory-only configuration for the AI engine.
///
/// Supersedes the legacy [AiApiConfig] (kept for back-compat during migration).
/// Adds the three capabilities the legacy config lacked:
///   * a [preset] (DeepSeek / OpenAI / Moonshot / Ollama / custom) so the
///     Settings UI can switch vendors;
///   * dual-model routing ([modelChat] / [modelJson]) so cheap conversational
///     calls can go to a smaller model;
///   * a [strictSchema] policy with auto-fallback.
///
/// The API key is held in memory only and is **never persisted** - this matches
/// the security stance of `AiApiConfig` (see `ai_api_config.dart:4-7`).
class AiEngineConfig {
  const AiEngineConfig({
    this.preset = kDeepseekPreset,
    required this.apiKey,
    String? modelChat,
    String? modelJson,
    this.strictSchema = StrictSchemaMode.auto,
    this.cacheEnabled = true,
    this.customBaseUrl,
    this.supportsReasoningOverride,
  })  : _modelChat = modelChat,
        _modelJson = modelJson;

  /// Selected provider preset. Drives the default Base URL unless [customBaseUrl]
  /// is set (only meaningful when [preset] is `custom`).
  final AiProviderPreset preset;

  /// Secret API key. Never logged or persisted.
  final String apiKey;

  /// Explicit override for whether the endpoint accepts reasoning payload
  /// fields. When `null` (default), [reasoningEnabled] falls back to the
  /// preset + host check. Mirrors the legacy `AiApiConfig.supportsReasoning`
  /// nullable flag so the migration bridge can preserve its exact semantics.
  final bool? supportsReasoningOverride;

  /// Raw chat-side model id, or `null` to fall back to [preset.defaultModel].
  /// Stored nullable so the const constructor can default to the preset without
  /// a non-const `preset.defaultModel` read in the initializer list.
  final String? _modelChat;

  /// Raw JSON-side model id, or `null` to fall back to [preset.defaultModel].
  final String? _modelJson;

  /// Model id for conversational / explanation calls. Defaults to the preset's
  /// default model when not specified.
  String get modelChat => _modelChat ?? preset.defaultModel;

  /// Model id for JSON-generation calls (course / lesson / transform / extract).
  /// Defaults to the preset's default model when not specified.
  String get modelJson => _modelJson ?? preset.defaultModel;

  /// Strict-JSON response-format policy.
  final StrictSchemaMode strictSchema;

  /// Master toggle for the response cache. Mirrors
  /// `ai_cache.py:Settings.ai_cache_enabled`.
  final bool cacheEnabled;

  /// User-supplied Base URL, used only when [preset] is `custom`. For named
  /// presets the preset's Base URL wins.
  final String? customBaseUrl;

  /// Effective Base URL: the custom URL for the `custom` preset, otherwise the
  /// preset's Base URL.
  String get baseUrl => preset.id == AiProvider.custom
      ? (customBaseUrl ?? '')
      : preset.baseUrl;

  /// Normalized chat-completions URL. Strips any trailing slash on [baseUrl]
  /// and appends `/chat/completions` if the user only provided the base. Mirrors
  /// `AiApiConfig.chatCompletionsUrl`.
  String get chatCompletionsUrl {
    var b = baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (b.endsWith('/chat/completions')) return b;
    return '$b/chat/completions';
  }

  /// Whether the endpoint accepts the `reasoning_effort` / `thinking` payload
  /// fields. An explicit [supportsReasoningOverride] wins; otherwise falls back
  /// to the preset's declared capability or the DeepSeek host check (mirrors
  /// `AiApiConfig.reasoningEnabled`).
  bool get reasoningEnabled =>
      supportsReasoningOverride ??
      (preset.supportsReasoning || isDeepSeekHost(baseUrl));

  /// Pick the model for a given call kind. Empty `modelChat` / `modelJson`
  /// (impossible here since the constructor defaults them, but defensive) falls
  /// back to the preset default. Mirrors `ai/config.py:select_model`.
  String selectModel(String kind) {
    switch (kind) {
      case 'chat':
        return modelChat.trim().isNotEmpty ? modelChat : preset.defaultModel;
      case 'json':
        return modelJson.trim().isNotEmpty ? modelJson : preset.defaultModel;
      default:
        return preset.defaultModel;
    }
  }

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      selectModel('chat').isNotEmpty;

  AiEngineConfig copyWith({
    AiProviderPreset? preset,
    String? apiKey,
    String? modelChat,
    String? modelJson,
    StrictSchemaMode? strictSchema,
    bool? cacheEnabled,
    String? customBaseUrl,
    bool? supportsReasoningOverride,
  }) {
    final newPreset = preset ?? this.preset;
    final presetChanged = newPreset.id != this.preset.id;
    return AiEngineConfig(
      preset: newPreset,
      apiKey: apiKey ?? this.apiKey,
      // Preserve the raw nullable value (not the resolved getter). When the
      // preset changed and the caller did not explicitly pass a model, drop the
      // old model so it falls back to the new preset's default rather than
      // freezing a model id that may be invalid for the new provider.
      modelChat: modelChat ?? (presetChanged ? null : _modelChat),
      modelJson: modelJson ?? (presetChanged ? null : _modelJson),
      strictSchema: strictSchema ?? this.strictSchema,
      cacheEnabled: cacheEnabled ?? this.cacheEnabled,
      customBaseUrl: customBaseUrl ?? this.customBaseUrl,
      supportsReasoningOverride:
          supportsReasoningOverride ?? this.supportsReasoningOverride,
    );
  }

  @override
  String toString() =>
      'AiEngineConfig(provider: ${preset.id}, baseUrl: $baseUrl, '
      'modelChat: $modelChat, modelJson: $modelJson)';
}
