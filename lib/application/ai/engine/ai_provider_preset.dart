// Built-in AI provider presets, ported from
// `tool/gui/src/backend/ai_presets.py:BUILTIN_PRESETS`.
//
// Each preset carries enough information to fill the Settings UI (Base URL,
// default + supported models, reasoning capability, docs link) so users can
// switch vendors without typing a Base URL every time. The Dart side mirrors
// the Python `ProviderPreset` / `apply_preset` contract so the two stay in
// lockstep.
//
// Pricing (the Python `PRICING` table) is intentionally NOT ported: the user
// scoped this round to provider switching + caching + streaming + cancel, and
// explicitly excluded usage/cost telemetry. Pricing can be layered back on
// later without touching this file's public surface.

/// Machine name of a supported provider. `custom` preserves whatever the user
/// typed (empty Base URL / model) instead of overwriting it.
enum AiProvider { deepseek, openai, moonshot, ollama, custom }

/// A provider preset carrying enough information to fill the Settings UI.
class AiProviderPreset {
  const AiProviderPreset({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.defaultModel,
    this.supportedModels = const [],
    this.supportsReasoning = false,
    this.docsUrl = '',
  });

  final AiProvider id;

  /// Human-readable label shown in the preset dropdown.
  final String label;

  /// Default Base URL for the OpenAI-compatible endpoint.
  final String baseUrl;

  /// Model id selected by default when the user picks this preset.
  final String defaultModel;

  /// Models known to work with this provider, offered as quick-pick options.
  final List<String> supportedModels;

  /// Whether the endpoint accepts `reasoning_effort` / `thinking` payload
  /// fields (DeepSeek's documented behavior).
  final bool supportsReasoning;

  /// Documentation link shown next to the preset for convenience.
  final String docsUrl;

  static const AiProviderPreset empty = AiProviderPreset(
    id: AiProvider.custom,
    label: '',
    baseUrl: '',
    defaultModel: '',
  );
}

/// DeepSeek preset as a named const so it can be used as a const default
/// (e.g. `AiEngineConfig`'s `preset` field). Map indexing is not a const
/// operation in Dart, so `kBuiltinPresets[AiProvider.deepseek]` cannot appear
/// in a const context - this named const can.
const AiProviderPreset kDeepseekPreset = AiProviderPreset(
  id: AiProvider.deepseek,
  label: 'DeepSeek',
  baseUrl: 'https://api.deepseek.com',
  defaultModel: 'deepseek-v4-flash',
  supportedModels: [
    'deepseek-v4-flash',
    'deepseek-v4-pro',
    'deepseek-chat',
    'deepseek-reasoner',
  ],
  supportsReasoning: true,
  docsUrl: 'https://platform.deepseek.com/',
);

const AiProviderPreset kOpenaiPreset = AiProviderPreset(
  id: AiProvider.openai,
  label: 'OpenAI',
  baseUrl: 'https://api.openai.com/v1',
  defaultModel: 'gpt-4o',
  supportedModels: [
    'gpt-4o',
    'gpt-4o-mini',
    'gpt-4-turbo',
    'gpt-3.5-turbo',
  ],
  supportsReasoning: false,
  docsUrl: 'https://platform.openai.com/',
);

const AiProviderPreset kMoonshotPreset = AiProviderPreset(
  id: AiProvider.moonshot,
  label: 'Moonshot AI',
  baseUrl: 'https://api.moonshot.cn/v1',
  defaultModel: 'moonshot-v1-8k',
  supportedModels: [
    'moonshot-v1-8k',
    'moonshot-v1-32k',
    'moonshot-v1-128k',
  ],
  supportsReasoning: false,
  docsUrl: 'https://platform.moonshot.cn/',
);

const AiProviderPreset kOllamaPreset = AiProviderPreset(
  id: AiProvider.ollama,
  label: 'Ollama (本地)',
  baseUrl: 'http://localhost:11434/v1',
  defaultModel: 'qwen2.5',
  supportedModels: ['qwen2.5', 'llama3', 'deepseek-coder-v2'],
  supportsReasoning: false,
  docsUrl: 'https://ollama.com/',
);

const AiProviderPreset kCustomPreset = AiProviderPreset(
  id: AiProvider.custom,
  label: '自定义',
  baseUrl: '',
  defaultModel: '',
  supportedModels: [],
  supportsReasoning: false,
);

/// Built-in presets keyed by [AiProvider]. Order matches
/// `ai_presets.py:provider_names()` (`deepseek, openai, moonshot, ollama,
/// custom`). Each value is a named const so the same instance can be referenced
/// in const contexts (e.g. config defaults).
const Map<AiProvider, AiProviderPreset> kBuiltinPresets = {
  AiProvider.deepseek: kDeepseekPreset,
  AiProvider.openai: kOpenaiPreset,
  AiProvider.moonshot: kMoonshotPreset,
  AiProvider.ollama: kOllamaPreset,
  AiProvider.custom: kCustomPreset,
};

/// All built-in providers in the canonical dropdown order.
List<AiProvider> providerOrder() => const [
      AiProvider.deepseek,
      AiProvider.openai,
      AiProvider.moonshot,
      AiProvider.ollama,
      AiProvider.custom,
    ];

/// Return the preset for [provider], falling back to the `custom` preset.
AiProviderPreset presetFor(AiProvider provider) =>
    kBuiltinPresets[provider] ?? kBuiltinPresets[AiProvider.custom]!;

/// Apply a preset to the current Base URL / model / reasoning triplet.
///
/// Mirrors `ai_presets.py:apply_preset`. For `custom`, the existing values are
/// preserved so the user keeps whatever they typed. For a named preset the
/// preset's Base URL, default model, and reasoning capability replace the
/// current values.
///
/// Returns `(newBaseUrl, newModel, newSupportsReasoning)`.
({String baseUrl, String model, bool supportsReasoning}) applyPreset({
  required AiProvider provider,
  required String baseUrl,
  required String model,
  required bool supportsReasoning,
}) {
  final preset = presetFor(provider);
  if (preset.id == AiProvider.custom) {
    return (baseUrl: baseUrl, model: model, supportsReasoning: supportsReasoning);
  }
  return (
    baseUrl: preset.baseUrl,
    model: preset.defaultModel,
    supportsReasoning: preset.supportsReasoning,
  );
}
