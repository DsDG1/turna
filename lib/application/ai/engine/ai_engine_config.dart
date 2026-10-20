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
///   * a [preset] (DeepSeek / MiMo / custom) so the
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

  /// Raw JSON-side model id; `null` means "same as the chat model"
  /// ([effectiveJsonModel]).
  final String? _modelJson;

  /// Model id for conversational / explanation calls. Defaults to the preset's
  /// default model when not specified. This is the raw display value — what
  /// actually goes on the wire is [effectiveChatModel].
  String get modelChat => _modelChat ?? preset.defaultModel;

  /// Model id for JSON-generation calls (course / lesson / transform / extract).
  /// Defaults to the preset's default model when not specified. This is the raw
  /// display value — leaving it blank means "inherit the chat model", which is
  /// what [effectiveJsonModel] resolves.
  String get modelJson => _modelJson ?? preset.defaultModel;

  /// 会话调用真正发出去的模型 id：`modelChat`（去首尾空白）→ 预设默认值 → 空串。
  ///
  /// 空串只可能出现在 `custom` 预设上——它没有默认模型。
  String get effectiveChatModel {
    final trimmed = modelChat.trim();
    return trimmed.isNotEmpty ? trimmed : preset.defaultModel.trim();
  }

  /// JSON 调用真正发出去的模型 id：`modelJson`（去首尾空白）→
  /// [effectiveChatModel]。
  ///
  /// **留空必须继承会话模型，不能把空串原样发出去。** 这条规则移植自
  /// `tool/gui/src/backend/ai/config.py:select_model` 的
  /// `model_json.strip() or self.model`；Dart 侧一度写成「回落到
  /// `preset.defaultModel`」，在 deepseek / mimo 预设下两者恰好同值，所以
  /// 看不出异常。`custom` 预设的默认模型是空串，于是请求带着 `model: ""`
  /// 上路，服务端只回一句 `unknown model`——用户看到的是「AI 对话能用，
  /// 学习诊断 / 定制复习 / 生成课程全挂」。
  String get effectiveJsonModel {
    final trimmed = modelJson.trim();
    return trimmed.isNotEmpty ? trimmed : effectiveChatModel;
  }

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
  String get baseUrl =>
      preset.id == AiProvider.custom ? (customBaseUrl ?? '') : preset.baseUrl;

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

  /// Pick the model id to send for a given call kind. `json` uses
  /// [effectiveJsonModel]; `chat` and any unknown kind use
  /// [effectiveChatModel]. Mirrors `ai/config.py:select_model`.
  String selectModel(String kind) => switch (kind) {
        'json' => effectiveJsonModel,
        _ => effectiveChatModel,
      };

  /// 一次请求需要 Base URL、密钥、模型 id 三样齐全。[effectiveJsonModel] 继承
  /// [effectiveChatModel]，所以 JSON 侧不可能在会话侧为空时还有值——检查会话
  /// 模型这一条即可覆盖两种调用。
  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      effectiveChatModel.isNotEmpty;

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
        'schemaVersion': schemaVersion,
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

  /// 持久化 JSON 的当前形状版本。删预设、改模型 id 这类「字段含义变了」的
  /// 改动必须同时提版本号，并在 [fromJson] 里处理旧形状。
  ///
  /// 版本史：
  ///   * 1（隐式，无该字段）— presetId 含 `kimi` / `qwen`；模型 id 为
  ///     `deepseek-v4-*` / `mimo-v2.5*`。
  ///   * 2（2026-10-20）— 服务商收敛为 deepseek / mimo / custom；
  ///     DeepSeek 升到 4.1、MiMo 升到 2.6。旧值按下表迁移。
  static const int schemaVersion = 2;

  /// Rebuild a config from its [toJson] output. Unknown / missing fields fall
  /// back to the constructor defaults, so a partial or older-shape record
  /// degrades gracefully instead of throwing.
  ///
  /// 迁移规则（schemaVersion < 2）：
  ///   * `presetId` 是已下线预设（`kimi` / `qwen`）→ 转成 `custom`，
  ///     Base URL 取该厂商原地址，模型沿用用户存的值（没有就取原默认值）。
  ///     **不能**让枚举兜底成 DeepSeek：那会拼出「deepseek 地址 + kimi 模型」
  ///     的必失败组合，且界面看不出异常。
  ///   * 模型 id 命中 [kRetiredModelAliases] 的旧名 → 换成新名。
  factory AiEngineConfig.fromJson(Map<String, dynamic> json) {
    final rawPreset = json['presetId'];
    final retired = rawPreset is String ? kRetiredPresets[rawPreset] : null;

    AiProvider? presetId;
    for (final p in AiProvider.values) {
      if (p.name == rawPreset) {
        presetId = p;
        break;
      }
    }

    final preset = retired != null
        ? kCustomPreset
        : (presetId != null ? presetFor(presetId) : kDeepseekPreset);
    final storedCustomBaseUrl = json['customBaseUrl'] as String?;

    String? migrateModel(String? raw) {
      if (raw == null) return null;
      final trimmed = raw.trim();
      // 空串是「没填」的另一种写法：旧设置页把空输入框原样存成 ''，归成 null
      // 才能让预设默认值 / 会话模型接得住它。
      if (trimmed.isEmpty) return null;
      return kRetiredModelAliases[trimmed] ?? trimmed;
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
      preset: preset,
      apiKey: (json['apiKey'] as String?) ?? '',
      // 老配置里模型可能是 null（从未手填），迁移到 custom 后没有预设默认值
      // 可回落，所以用原厂商的默认模型兜底；用户手填过的值原样保留。
      modelChat:
          migrateModel(json['modelChat'] as String?) ?? retired?.defaultModel,
      modelJson:
          migrateModel(json['modelJson'] as String?) ?? retired?.defaultModel,
      strictSchema: strict ?? StrictSchemaMode.auto,
      cacheEnabled: (json['cacheEnabled'] as bool?) ?? true,
      customBaseUrl: storedCustomBaseUrl ?? retired?.baseUrl,
      supportsReasoningOverride: json['supportsReasoningOverride'] as bool?,
    );
  }
}
