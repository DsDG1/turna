// Project imports:
import 'package:turna/application/ai/engine/ai_provider_preset.dart';

/// Strict-JSON response-format policy. Mirrors `ai/config.py:AiApiConfig.strict_schema`.
///
/// - [auto]: try `json_schema`; if the provider rejects it (HTTP 400 / "schema"
///   family), fall back to `json_object` and remember the probe for the process.
/// - [on]: force `json_schema` and surface any rejection as an error.
/// - [off]: force `json_object` (the loosest JSON mode).
enum StrictSchemaMode { auto, on, off }

/// Unified configuration for the AI engine.
///
/// Supersedes the legacy [AiApiConfig] (kept for back-compat during migration).
/// Adds the three capabilities the legacy config lacked:
///   * a [preset] (DeepSeek / Kimi / Qwen / MiMo / custom) so the
///     Settings UI can switch vendors;
///   * dual-model routing ([modelChat] / [modelJson]) so cheap conversational
///     calls can go to a smaller model;
///   * a [strictSchema] policy with auto-fallback.
///
/// This class is a plain immutable value; persistence is the responsibility of
/// [AiEngineConfigHolder]. Non-secret fields are serialized to Shared-
/// Preferences while the API key lives in the platform secure store
/// ([SecureCredentialStore]); the prefs blob therefore never contains the key.
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

  /// Secret API key. Never logged; persisted to the device by
  /// [AiEngineConfigHolder] so it survives an app restart.
  final String apiKey;

  /// Explicit user choice for whether to send reasoning payload fields. When
  /// `null` (default), [reasoningEnabled] resolves to `false` — reasoning is
  /// opt-in via the settings toggle, never silently on. The preset's
  /// [AiProviderPreset.supportsReasoning] is only a capability hint shown in
  /// the UI, not the effective state.
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

  /// Whether the engine sends `reasoning_effort` / `thinking` payload fields.
  /// Opt-in: an explicit [supportsReasoningOverride] wins; otherwise reasoning
  /// is off. The preset's `supportsReasoning` flag is only a UI capability hint
  /// and does not enable reasoning on its own.
  bool get reasoningEnabled => supportsReasoningOverride ?? false;

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

  // ─── Serialization (for AiEngineConfigHolder persistence) ───────────────
  //
  // Round-trips the config to JSON so it can be stored in SharedPreferences
  // and reloaded on the next launch. The preset is serialized by its enum
  // [AiProvider.name] and rebuilt via [presetFor]; for the `custom` preset the
  // Base URL lives in [customBaseUrl], so no extra URL field is needed.

  Map<String, dynamic> toJson({bool includeApiKey = false}) =>
      <String, dynamic>{
        'presetId': preset.id.name,
        // Secrets are excluded by default: the plaintext prefs blob must
        // never carry the API key (Plan 2 §6.3). The legacy inclusive form is
        // used only when *reading back* the pre-migration blob.
        if (includeApiKey) 'apiKey': apiKey,
        'modelChat': _modelChat,
        'modelJson': _modelJson,
        'strictSchema': strictSchema.name,
        'cacheEnabled': cacheEnabled,
        'customBaseUrl': customBaseUrl,
        'supportsReasoningOverride': supportsReasoningOverride,
      };

  /// Rebuild a config from its [toJson] output. Unknown / missing fields fall
  /// back to the constructor defaults, so a partial or older-shape record
  /// degrades gracefully instead of throwing.
  factory AiEngineConfig.fromJson(Map<String, dynamic> json) {
    AiProvider? presetId;
    final rawPreset = json['presetId'];
    if (rawPreset is String) {
      for (final p in AiProvider.values) {
        if (p.name == rawPreset) {
          presetId = p;
          break;
        }
      }
    }
    StrictSchemaMode? strict;
    final rawStrict = json['strictSchema'];
    if (rawStrict is String) {
      for (final m in StrictSchemaMode.values) {
        if (m.name == rawStrict) {
          strict = m;
          break;
        }
      }
    }
    return AiEngineConfig(
      preset: presetId != null ? presetFor(presetId) : kDeepseekPreset,
      apiKey: (json['apiKey'] as String?) ?? '',
      modelChat: json['modelChat'] as String?,
      modelJson: json['modelJson'] as String?,
      strictSchema: strict ?? StrictSchemaMode.auto,
      cacheEnabled: (json['cacheEnabled'] as bool?) ?? true,
      customBaseUrl: json['customBaseUrl'] as String?,
      supportsReasoningOverride: json['supportsReasoningOverride'] as bool?,
    );
  }
}
