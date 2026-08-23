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
enum AiProvider { deepseek, kimi, qwen, mimo, custom }

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

  /// Whether the provider's models accept `reasoning_effort` / `thinking`
  /// payload fields (DeepSeek / Kimi / Qwen / MiMo all do). This is a
  /// *capability* hint, not the effective toggle: the user-facing reasoning
  /// switch lives on [AiEngineConfig] and defaults to off.
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
    'deepseek-v4-flash-vision-exp',
  ],
  supportsReasoning: true,
  docsUrl: 'https://platform.deepseek.com/',
);

const AiProviderPreset kKimiPreset = AiProviderPreset(
  id: AiProvider.kimi,
  label: 'Kimi',
  baseUrl: 'https://api.moonshot.cn/v1',
  defaultModel: 'kimi-k3',
  supportedModels: [
    'kimi-k3',
    'kimi-k2.7-code',
  ],
  supportsReasoning: true,
  docsUrl: 'https://platform.kimi.com/',
);

const AiProviderPreset kQwenPreset = AiProviderPreset(
  id: AiProvider.qwen,
  label: 'Qwen',
  baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
  defaultModel: 'qwen3.8-max',
  supportedModels: [
    'qwen3.8-max',
    'qwen3.7-plus',
    'qwen3.7-flash',
    'qwen3.5-omni-plus',
  ],
  supportsReasoning: true,
  docsUrl: 'https://help.aliyun.com/zh/model-studio/',
);

const AiProviderPreset kMimoPreset = AiProviderPreset(
  id: AiProvider.mimo,
  label: 'MiMo',
  baseUrl: 'https://api.xiaomimimo.com/v1',
  defaultModel: 'mimo-v2.5-pro',
  supportedModels: [
    'mimo-v2.5-pro',
    'mimo-v2.5',
  ],
  supportsReasoning: true,
  docsUrl: 'https://mimo.mi.com/docs/zh-CN/quick-start/summary/model',
);

const AiProviderPreset kCustomPreset = AiProviderPreset(
  id: AiProvider.custom,
  label: '自定义',
  baseUrl: '',
  defaultModel: '',
  supportedModels: [],
  supportsReasoning: false,
);

/// Built-in presets keyed by [AiProvider]. Each value is a named const so the
/// same instance can be referenced in const contexts (e.g. config defaults).
const Map<AiProvider, AiProviderPreset> kBuiltinPresets = {
  AiProvider.deepseek: kDeepseekPreset,
  AiProvider.kimi: kKimiPreset,
  AiProvider.qwen: kQwenPreset,
  AiProvider.mimo: kMimoPreset,
  AiProvider.custom: kCustomPreset,
};

/// All built-in providers in the canonical dropdown order.
List<AiProvider> providerOrder() => const [
      AiProvider.deepseek,
      AiProvider.kimi,
      AiProvider.qwen,
      AiProvider.mimo,
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
    return (
      baseUrl: baseUrl,
      model: model,
      supportsReasoning: supportsReasoning
    );
  }
  return (
    baseUrl: preset.baseUrl,
    model: preset.defaultModel,
    supportsReasoning: preset.supportsReasoning,
  );
}
