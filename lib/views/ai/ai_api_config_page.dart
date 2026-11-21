// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/engine/ai_provider_preset.dart';
import 'package:turna/core/endpoint_url_policy.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_api_config_sections.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/views/widgets/directory_rows.dart';
import 'package:turna/views/widgets/optional_provider.dart';
import 'package:turna/views/widgets/turna_select.dart';
import 'package:turna/views/widgets/turna_sheet.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// AI connection settings page (高级 → AI 连接, Plan 2 §6.2).
///
/// R14 口径：偏好目录**深页**模式 —— 分区标题 + 连续表单行（值右对齐，
/// [DirectoryValueRow]），保存 / 测试操作收进底部动作带
/// （[SessionActionBand]）。Scope is *connection only*: provider, API key,
/// models, custom Base URL, test connection, clear credentials. Explain-style
/// preferences live on the AI Hub.
///
/// Editing model (Plan 2 §4.10 / §6.2): text edits update a local draft and
/// are committed via a ≥500 ms debounce plus an explicit 保存 button — never
/// per keystroke. The API key is never prefilled into the field; it starts
/// empty and shows the masked stored key as the hint, so screenshots of the
/// page can't leak the secret. The key persists separately in the platform
/// secure store (see [AiEngineConfigHolder]); on platforms without one the
/// page explains the session-only limitation instead of silently falling back
/// to plaintext prefs.
///
/// Base URL 校验口径不变：[EndpointUrlPolicy.normalize] 是唯一真源。
@RoutePage()
class AiApiConfigPage extends StatefulWidget {
  const AiApiConfigPage({super.key});

  @override
  State<AiApiConfigPage> createState() => _AiApiConfigPageState();
}

class _AiApiConfigPageState extends State<AiApiConfigPage> {
  late final AiEngineConfigHolder _holder;
  late AiEngineConfig _draft;

  /// Starts empty: the stored key is never echoed into an editable field.
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _modelChatCtrl;
  late final TextEditingController _modelJsonCtrl;

  Timer? _commitDebounce;
  static const _commitDebounceMs = 500;

  String? _baseUrlError;

  /// Lets the page reset the probe result when the config underneath changes
  /// (preset switch, clear key, restore defaults).
  final GlobalKey<AiConfigConnectionTestSectionState> _probeKey =
      GlobalKey<AiConfigConnectionTestSectionState>();

  @override
  void initState() {
    super.initState();
    _holder = readOptionalProvider<AiEngineConfigHolder>(context)!;
    _draft = _holder.config;
    _apiKeyCtrl = TextEditingController();
    _baseUrlCtrl = TextEditingController(text: _draft.baseUrl);
    _modelChatCtrl = TextEditingController(text: _draft.modelChat);
    _modelJsonCtrl = TextEditingController(text: _draft.modelJson);
  }

  @override
  void dispose() {
    // The debounce timer is cancelled here so it can never fire after the
    // controllers go away. A pending draft is flushed synchronously first
    // — leaving the page (route pop, widget-tree replacement or teardown)
    // must never silently lose the user's last edit.
    _commitDebounce?.cancel();
    _flushDraftForDispose();
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelChatCtrl.dispose();
    _modelJsonCtrl.dispose();
    super.dispose();
  }

  /// Dispose-safe variant of [_commitDraft]: no setState, no controller
  /// mutation — just persist the pending text before the controllers die.
  void _flushDraftForDispose() {
    final storedKey = _holder.config.apiKey;
    final typedKey = _apiKeyCtrl.text.trim();
    var normalizedBaseUrl = _draft.customBaseUrl;
    if (_draft.preset.id == AiProvider.custom) {
      final (value, error) = _normalizeBaseUrl(_baseUrlCtrl.text);
      if (error != null) return; // invalid URL: keep the last good draft
      normalizedBaseUrl = value;
    }
    final next = _draft.copyWith(
      apiKey: typedKey.isEmpty ? storedKey : typedKey,
      customBaseUrl: normalizedBaseUrl,
      modelChat: _modelChatCtrl.text.trim(),
      modelJson: _modelJsonCtrl.text.trim(),
    );
    if (next == _draft) return;
    // Fire-and-forget: the holder persists through its credential store;
    // nothing here may touch this State again. Deferred by one microtask:
    // dispose runs inside finalizeTree's state lock, so a synchronous
    // updateConfig → notifyListeners would try to mark provider dependents
    // while the tree is locked ("widget tree was locked" assert). The
    // microtask runs after the frame, with the lock released.
    unawaited(Future.microtask(() => _holder.updateConfig(next)));
  }

  // ─── Draft commit (debounced + explicit) ─────────────────────────────

  void _scheduleCommit() {
    _commitDebounce?.cancel();
    _commitDebounce = Timer(
      const Duration(milliseconds: _commitDebounceMs),
      _commitDraft,
    );
  }

  /// Resolve the Base URL text into a normalized value, or an error when the
  /// scheme/host is unusable. Production requires https; local plain-HTTP
  /// endpoints are a development convenience only (Plan 2 §6.2).
  ///
  /// The decision itself lives in [EndpointUrlPolicy] so this page and the
  /// WebDAV settings page cannot drift into accepting different endpoints;
  /// this method only maps the shared reason onto AI-specific wording.
  (String, String?) _normalizeBaseUrl(String raw) {
    final (:value, :problem) = EndpointUrlPolicy.normalize(raw);
    final error = switch (problem) {
      null => null,
      EndpointUrlProblem.empty => AppStrings.aiConfigBaseUrlEmpty,
      EndpointUrlProblem.malformed => AppStrings.aiConfigBaseUrlInvalid,
      EndpointUrlProblem.unsupportedScheme =>
        AppStrings.aiConfigBaseUrlInvalidScheme,
      EndpointUrlProblem.httpsRequired => AppStrings.aiConfigBaseUrlHttpsOnly,
    };
    return (value, error);
  }

  Future<void> _commitDraft() async {
    final storedKey = _holder.config.apiKey;
    final typedKey = _apiKeyCtrl.text.trim();
    var normalizedBaseUrl = _draft.customBaseUrl;
    String? baseUrlError;
    if (_draft.preset.id == AiProvider.custom) {
      final (value, error) = _normalizeBaseUrl(_baseUrlCtrl.text);
      normalizedBaseUrl = value;
      baseUrlError = error;
    }
    if (mounted) setState(() => _baseUrlError = baseUrlError);
    if (baseUrlError != null) return;

    final next = _draft.copyWith(
      // Empty field = keep the stored secret; typing replaces it.
      apiKey: typedKey.isEmpty ? storedKey : typedKey,
      customBaseUrl: normalizedBaseUrl,
      modelChat: _modelChatCtrl.text.trim(),
      modelJson: _modelJsonCtrl.text.trim(),
    );
    if (next == _draft) return;
    _draft = next;
    if (mounted) setState(() {});
    await _holder.updateConfig(next);
    // The key field only ever holds freshly typed input; it's consumed now.
    if (mounted && _apiKeyCtrl.text.isNotEmpty) {
      _apiKeyCtrl.clear();
    }
  }

  Future<void> _saveNow() async {
    _commitDebounce?.cancel();
    await _commitDraft();
    if (mounted) {
      TurnaSnackBar.show(context, AppStrings.aiConfigSaved);
    }
  }

  void _onPresetChanged(AiProvider next) {
    if (next == _draft.preset.id) return;
    final preset = presetFor(next);
    setState(() {
      _draft = _draft.copyWith(
        preset: preset,
        customBaseUrl:
            preset.id == AiProvider.custom ? _draft.customBaseUrl : null,
        // copyWith drops models on a preset change so the new vendor's
        // default model wins; mirror that in the text fields. Reasoning is
        // opt-in and defaults off, so reset the toggle on every switch.
        modelChat: null,
        modelJson: null,
        supportsReasoningOverride: false,
      );
      _baseUrlCtrl.text = preset.baseUrl;
      _modelChatCtrl.text = preset.defaultModel;
      _modelJsonCtrl.text = preset.defaultModel;
      _baseUrlError = null;
    });
    _probeKey.currentState?.clearResult();
    unawaited(_holder.updateConfig(_draft));
  }

  /// The draft config with the *effective* key (typed or stored) — used by
  /// the connection probe so testing never persists a failing config.
  AiEngineConfig get _effectiveDraft {
    final typed = _apiKeyCtrl.text.trim();
    if (typed.isEmpty) return _draft;
    return _draft.copyWith(apiKey: typed);
  }

  Future<void> _clearCredentials() async {
    final confirmed = await showTurnaConfirmDialog(
      context: context,
      title: AppStrings.aiConfigClearKeyTitle,
      message: AppStrings.aiConfigClearKeyMessage,
      confirmLabel: AppStrings.aiConfigClearKeyConfirm,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _holder.clearApiKey();
    if (mounted) {
      setState(() {
        _draft = _holder.config;
      });
      _probeKey.currentState?.clearResult();
      TurnaSnackBar.show(context, AppStrings.aiConfigClearKeyDone);
    }
  }

  Future<void> _restoreDefaults() async {
    final confirmed = await showTurnaConfirmDialog(
      context: context,
      title: AppStrings.aiConfigRestoreDefaultsTitle,
      message: AppStrings.aiConfigRestoreDefaultsMessage,
      confirmLabel: AppStrings.aiConfigRestoreDefaultsConfirm,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _holder.updateConfig(const AiEngineConfig(apiKey: ''));
    if (mounted) {
      setState(() {
        _draft = _holder.config;
        _apiKeyCtrl.clear();
        _baseUrlCtrl.text = _draft.baseUrl;
        _modelChatCtrl.text = _draft.modelChat;
        _modelJsonCtrl.text = _draft.modelJson;
      });
      _probeKey.currentState?.clearResult();
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Intercept back so any pending debounced edit is flushed *before* the
    // route pops — while the widget is still mounted and the framework is not
    // locked. Flushing in dispose() would call notifyListeners during unmount
    // and trip "markNeedsBuild called when widget tree was locked".
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        _commitDebounce?.cancel();
        await _commitDraft();
        // Unconditional pop bypasses canPop so this callback doesn't re-enter.
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: TurnaTheme.surfaceColor(context),
        appBar: AppBar(
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: TurnaTheme.brandTeal,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.settingsAiApiConfigSheetTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
        // 键盘让位由 Scaffold 的 resize + 底部动作带承担；正文不再叠加
        // viewInsets 内边距（否则键盘弹出时出现双倍空档）。
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(
              left: AppSpacing.pageMargin,
              right: AppSpacing.pageMargin,
              top: AppSpacing.md,
              bottom: AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AiConfigStatusLine(
                  isComplete: _effectiveDraft.isComplete,
                  presetLabel: _draft.preset.label,
                  modelChatText: _modelChatCtrl.text.trim(),
                ),
                const SizedBox(height: AppSpacing.md),
                const AiConfigCredentialSafetyNotice(),
                const SizedBox(height: AppSpacing.md),
                // 接口类型 + 数据流向 + 责任归属：用户按实填了第三方 Key，
                // 就必须在填写现场说清「请求发给谁、谁负责」。
                const AiConfigEndpointScopeNotice(),
                const SizedBox(height: AppSpacing.xl),

                // ── 分区：连接 ──
                AiConfigSectionHeading(AppStrings.aiConfigGroupConnection),
                Text(
                  AppStrings.aiConfigProviderSectionHint,
                  style: AppTextStyles.captionSm(context).copyWith(
                    color: TurnaTheme.textHintColor(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm + 2),
                TurnaSegmented<AiProvider>(
                  selected: _draft.preset.id,
                  onChanged: _onPresetChanged,
                  segments: [
                    for (final p in providerOrder())
                      ButtonSegment(value: p, label: Text(presetFor(p).label)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AiConfigBaseUrlBlock(
                  isCustom: _draft.preset.id == AiProvider.custom,
                  controller: _baseUrlCtrl,
                  errorText: _baseUrlError,
                  presetBaseUrl: _draft.preset.baseUrl,
                  onChanged: (_) => _scheduleCommit(),
                ),
                const SizedBox(height: AppSpacing.sm + 2),
                Text(
                  AppStrings.aiConfigOpenAiCompatHint,
                  style: AppTextStyles.captionSm(context).copyWith(
                    color: TurnaTheme.textHintColor(context),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ── 分区：密钥与模型 ──
                AiConfigSectionHeading(AppStrings.aiConfigGroupModels),
                _textEntry(
                  context,
                  label: AppStrings.settingsApiKeyLabel,
                  child: AiConfigApiKeyField(
                    controller: _apiKeyCtrl,
                    hint: _draft.apiKey.isEmpty
                        ? AppStrings.settingsApiKeyHint
                        : AppStrings.aiConfigKeyStoredHint(
                            _maskKey(_draft.apiKey)),
                    onChanged: (_) => _scheduleCommit(),
                  ),
                ),
                _textEntry(
                  context,
                  label: AppStrings.aiHubFieldModelChat,
                  child: TextField(
                    controller: _modelChatCtrl,
                    decoration: aiSheetInputDecoration(
                      context,
                      hint: AppStrings.settingsModelHint,
                    ),
                    onChanged: (_) => _scheduleCommit(),
                  ),
                ),
                if (_draft.preset.supportedModels.isNotEmpty)
                  AiConfigModelQuickPick(
                    models: _draft.preset.supportedModels,
                    selectedModel: _modelChatCtrl.text.trim(),
                    onSelected: (model) {
                      _modelChatCtrl.text = model;
                      _scheduleCommit();
                    },
                  ),
                _textEntry(
                  context,
                  label: AppStrings.aiHubFieldModelJson,
                  child: TextField(
                    controller: _modelJsonCtrl,
                    decoration: aiSheetInputDecoration(
                      context,
                      // 留空 = 跟聊天模型一样。不写清楚的话，`custom` 预设下
                      // 空着会被当成「没配」——服务端只回 unknown model。
                      hint: AppStrings.aiHubFieldModelJsonHint,
                    ),
                    onChanged: (_) => _scheduleCommit(),
                  ),
                ),
                if (_draft.preset.supportedModels.isNotEmpty)
                  AiConfigModelQuickPick(
                    models: _draft.preset.supportedModels,
                    selectedModel: _modelJsonCtrl.text.trim(),
                    onSelected: (model) {
                      _modelJsonCtrl.text = model;
                      _scheduleCommit();
                    },
                  ),
                // 深度思考：开关行（label 左、控件右）+ 说明小字。
                DirectoryValueRow(
                  label: AppStrings.aiConfigReasoningToggle,
                  control: Switch(
                    value: _draft.reasoningEnabled,
                    onChanged: (value) {
                      setState(() {
                        _draft =
                            _draft.copyWith(supportsReasoningOverride: value);
                      });
                      _scheduleCommit();
                    },
                  ),
                  showDivider: false,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _draft.preset.supportsReasoning
                        ? AppStrings.aiConfigReasoningSupportedHint
                        : AppStrings.aiConfigReasoningUnsupportedHint,
                    style: AppTextStyles.captionSm(context).copyWith(
                      color: TurnaTheme.textHintColor(context),
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ── 危险操作 ──
                AiConfigDangerRow(
                  onClear: _clearCredentials,
                  onRestore: _restoreDefaults,
                ),
                const SizedBox(height: AppSpacing.md),
                const AiConfigFooterHint(),
              ],
            ),
          ),
        ),
        // 保存 / 测试收进底部动作带：位置稳定，键盘弹出时仍可见。
        bottomNavigationBar: AiConfigConnectionTestSection(
          key: _probeKey,
          configGetter: () => _effectiveDraft,
          onSave: _saveNow,
        ),
      ),
    );
  }

  /// 文本输入行：label 在上、输入域占整行（秘密与模型名无法右对齐展示）。
  Widget _textEntry(
    BuildContext context, {
    required String label,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.captionSm(context).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm - 2),
          child,
        ],
      ),
    );
  }
}

String _maskKey(String key) {
  final trimmed = key.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.length <= 8) return '${trimmed[0]}…(${trimmed.length})';
  return '${trimmed.substring(0, 3)}…${trimmed.substring(trimmed.length - 4)}';
}
