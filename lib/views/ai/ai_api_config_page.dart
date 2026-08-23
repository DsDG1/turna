// Flutter imports:
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/engine/ai_provider_preset.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/turna_select.dart';

/// AI connection settings page (高级 → AI 连接, Plan 2 §6.2).
///
/// Scope is *connection only*: provider, API key, models, custom Base URL,
/// test connection, clear credentials. Explain-style preferences live on the
/// AI Hub; strict-schema / cache diagnostics moved to 旧版与兼容性 and
/// 存储与性能.
///
/// Editing model (Plan 2 §4.10 / §6.2): text edits update a local draft and
/// are committed via a ≥500 ms debounce plus an explicit 保存 button — never
/// per keystroke. The API key is never prefilled into the field; it starts
/// empty and shows the masked stored key as the hint, so screenshots of the
/// page can't leak the secret. The key persists separately in the platform
/// secure store (see [AiEngineConfigHolder]); on platforms without one the
/// page explains the session-only limitation instead of silently falling back
/// to plaintext prefs.
@RoutePage()
class AiApiConfigPage extends StatefulWidget {
  const AiApiConfigPage({super.key});

  @override
  State<AiApiConfigPage> createState() => _AiApiConfigPageState();
}

class _AiApiConfigPageState extends State<AiApiConfigPage> {
  late AiEngineConfig _draft;

  /// Starts empty: the stored key is never echoed into an editable field.
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _modelChatCtrl;
  late final TextEditingController _modelJsonCtrl;

  Timer? _commitDebounce;
  static const _commitDebounceMs = 500;

  /// True once dispose started: `mounted` is still true *during* dispose, so
  /// the flush path needs an explicit guard against setState-after-dispose.
  bool _disposed = false;

  bool get _canSetState => mounted && !_disposed;

  bool _probing = false;
  bool _obscureKey = true;
  ({bool ok, int latencyMs, String errorCategory})? _probeResult;
  String? _baseUrlError;

  @override
  void initState() {
    super.initState();
    final holder = getIt<AiEngineConfigHolder>();
    _draft = holder.config;
    _apiKeyCtrl = TextEditingController();
    _baseUrlCtrl = TextEditingController(text: _draft.baseUrl);
    _modelChatCtrl = TextEditingController(text: _draft.modelChat);
    _modelJsonCtrl = TextEditingController(text: _draft.modelJson);
  }

  @override
  void dispose() {
    // Never silently drop a pending draft: flush the debounce before the
    // controllers go away (Plan 2 §5.4).
    _disposed = true;
    _commitDebounce?.cancel();
    unawaited(_commitDraft());
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelChatCtrl.dispose();
    _modelJsonCtrl.dispose();
    super.dispose();
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
  (String, String?) _normalizeBaseUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return ('', AppStrings.aiConfigBaseUrlEmpty);
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    final Uri uri;
    try {
      uri = Uri.parse(value);
    } catch (_) {
      return (value, AppStrings.aiConfigBaseUrlInvalid);
    }
    final isHttp = uri.scheme == 'http';
    final isHttps = uri.scheme == 'https';
    if (!isHttp && !isHttps) {
      return (value, AppStrings.aiConfigBaseUrlInvalidScheme);
    }
    if (uri.host.isEmpty) {
      return (value, AppStrings.aiConfigBaseUrlInvalid);
    }
    final isLoopback = uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '[::1]';
    if (isHttp && !isLoopback && !kDebugMode) {
      return (value, AppStrings.aiConfigBaseUrlHttpsOnly);
    }
    return (value, null);
  }

  Future<void> _commitDraft() async {
    final holder = getIt<AiEngineConfigHolder>();
    final storedKey = holder.config.apiKey;
    final typedKey = _apiKeyCtrl.text.trim();
    var normalizedBaseUrl = _draft.customBaseUrl;
    String? baseUrlError;
    if (_draft.preset.id == AiProvider.custom) {
      final (value, error) = _normalizeBaseUrl(_baseUrlCtrl.text);
      normalizedBaseUrl = value;
      baseUrlError = error;
    }
    if (_canSetState) setState(() => _baseUrlError = baseUrlError);
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
    if (_canSetState) setState(() {});
    await holder.updateConfig(next);
    // The key field only ever holds freshly typed input; it's consumed now.
    if (!_disposed && _apiKeyCtrl.text.isNotEmpty) {
      _apiKeyCtrl.clear();
    }
  }

  Future<void> _saveNow() async {
    _commitDebounce?.cancel();
    await _commitDraft();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.aiConfigSaved)),
      );
    }
  }

  void _onPresetChanged(AiProvider next) {
    if (next == _draft.preset.id) return;
    final preset = presetFor(next);
    setState(() {
      _draft = _draft.copyWith(
        preset: preset,
        customBaseUrl: preset.id == AiProvider.custom
            ? _draft.customBaseUrl
            : null,
        // copyWith drops models on a preset change so the new vendor's
        // default model wins; mirror that in the text fields.
        modelChat: null,
        modelJson: null,
        supportsReasoningOverride: preset.supportsReasoning,
      );
      _baseUrlCtrl.text = preset.baseUrl;
      _modelChatCtrl.text = preset.defaultModel;
      _modelJsonCtrl.text = preset.defaultModel;
      _probeResult = null;
      _baseUrlError = null;
    });
    unawaited(getIt<AiEngineConfigHolder>().updateConfig(_draft));
  }

  /// The draft config with the *effective* key (typed or stored) — used by
  /// the connection probe so testing never persists a failing config.
  AiEngineConfig get _effectiveDraft {
    final typed = _apiKeyCtrl.text.trim();
    if (typed.isEmpty) return _draft;
    return _draft.copyWith(apiKey: typed);
  }

  Future<void> _testConnection() async {
    final draft = _effectiveDraft;
    if (!draft.isComplete) return;
    setState(() => _probing = true);
    try {
      final result = await getIt<AiEngine>().probeConnection(draft);
      if (!mounted) return;
      setState(() {
        _probing = false;
        _probeResult = (
          ok: result.ok,
          latencyMs: result.latencyMs,
          errorCategory: result.ok
              ? ''
              : _classifyProbeError(result.error, result.latencyMs),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _probing = false;
        _probeResult = (
          ok: false,
          latencyMs: 0,
          errorCategory: _classifyProbeError(error.toString(), 0),
        );
      });
    }
  }

  String _classifyProbeError(String message, int latencyMs) {
    final m = message.toLowerCase();
    if (m.contains('timeout') || m.contains('timed out') ||
        m.contains('deadline')) {
      return AppStrings.aiConfigProbeTimeout;
    }
    if (m.contains('failed host') || m.contains('dns') ||
        m.contains('no address') || m.contains('connection refused')) {
      return AppStrings.aiConfigProbeNetwork;
    }
    if (m.contains('handshake') || m.contains('certificate') ||
        m.contains('tls')) {
      return AppStrings.aiConfigProbeTls;
    }
    if (m.contains('401') || m.contains('403') ||
        m.contains('unauthorized') || m.contains('invalid api key') ||
        m.contains('authentication')) {
      return AppStrings.aiConfigProbeAuth;
    }
    if (m.contains('429') || m.contains('rate limit') ||
        m.contains('quota')) {
      return AppStrings.aiConfigProbeRateLimit;
    }
    if (m.contains('404') || m.contains('model') && m.contains('not')) {
      return AppStrings.aiConfigProbeModel;
    }
    if (m.contains('json') || m.contains('format') ||
        m.contains('decode')) {
      return AppStrings.aiConfigProbeFormat;
    }
    return AppStrings.aiConfigProbeUnknown;
  }

  Future<void> _clearCredentials() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.aiConfigClearKeyTitle),
        content: Text(AppStrings.aiConfigClearKeyMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppStrings.aiConfigClearKeyConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await getIt<AiEngineConfigHolder>().clearApiKey();
    if (mounted) {
      setState(() {
        _draft = getIt<AiEngineConfigHolder>().config;
        _probeResult = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.aiConfigClearKeyDone)),
      );
    }
  }

  Future<void> _restoreDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.aiConfigRestoreDefaultsTitle),
        content: Text(AppStrings.aiConfigRestoreDefaultsMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppStrings.aiConfigRestoreDefaultsConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await getIt<AiEngineConfigHolder>()
        .updateConfig(const AiEngineConfig(apiKey: ''));
    if (mounted) {
      setState(() {
        _draft = getIt<AiEngineConfigHolder>().config;
        _apiKeyCtrl.clear();
        _baseUrlCtrl.text = _draft.baseUrl;
        _modelChatCtrl.text = _draft.modelChat;
        _modelJsonCtrl.text = _draft.modelJson;
        _probeResult = null;
      });
    }
  }

  static String _maskKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= 8) return '${trimmed[0]}…(${trimmed.length})';
    return '${trimmed.substring(0, 3)}…${trimmed.substring(trimmed.length - 4)}';
  }

  ({IconData icon, Color color}) _providerVisual(AiProvider p) {
    switch (p) {
      case AiProvider.deepseek:
        return (icon: Icons.bolt_rounded, color: TurnaTheme.brandSky);
      case AiProvider.openai:
        return (
          icon: Icons.auto_awesome_rounded,
          color: TurnaTheme.brandTeal
        );
      case AiProvider.moonshot:
        return (
          icon: Icons.nights_stay_rounded,
          color: TurnaTheme.amethystLeague
        );
      case AiProvider.ollama:
        return (icon: Icons.memory_rounded, color: TurnaTheme.warning);
      case AiProvider.custom:
        return (icon: Icons.tune_rounded, color: TurnaTheme.brandReed);
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: TurnaTheme.surfaceColor(context),
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: TurnaTheme.amethystLeague,
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
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: media.viewInsets.bottom + 28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _statusHero(context),
              const SizedBox(height: 12),
              const _CredentialSafetyNotice(),
              const SizedBox(height: 16),
              AiGroupCard(
                icon: Icons.hub_rounded,
                title: AppStrings.aiConfigGroupConnection,
                children: [
                  _fieldLabel(context, AppStrings.aiConfigProviderSectionHint),
                  const SizedBox(height: 10),
                  _providerGrid(context),
                  const SizedBox(height: 14),
                  _baseUrlBlock(context),
                ],
              ),
              const SizedBox(height: 12),
              AiGroupCard(
                icon: Icons.key_rounded,
                title: AppStrings.aiConfigGroupModels,
                children: [
                  _fieldLabel(context, AppStrings.settingsApiKeyLabel),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _apiKeyCtrl,
                    obscureText: _obscureKey,
                    autofillHints: const [AutofillHints.password],
                    decoration: aiSheetInputDecoration(
                      context,
                      hint: _draft.apiKey.isEmpty
                          ? AppStrings.settingsApiKeyHint
                          : AppStrings.aiConfigKeyStoredHint(
                              _maskKey(_draft.apiKey)),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: TurnaTheme.textHintColor(context),
                        ),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                    onChanged: (_) => _scheduleCommit(),
                  ),
                  const SizedBox(height: 12),
                  _fieldLabel(context, AppStrings.aiHubFieldModelChat),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _modelChatCtrl,
                    decoration: aiSheetInputDecoration(
                      context,
                      hint: AppStrings.settingsModelHint,
                    ),
                    onChanged: (_) => _scheduleCommit(),
                  ),
                  if (_draft.preset.supportedModels.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _modelQuickPick(context),
                  ],
                  const SizedBox(height: 12),
                  _fieldLabel(context, AppStrings.aiHubFieldModelJson),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _modelJsonCtrl,
                    decoration: aiSheetInputDecoration(
                      context,
                      hint: AppStrings.settingsModelHint,
                    ),
                    onChanged: (_) => _scheduleCommit(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: aiSheetSecondaryButtonStyle(),
                      onPressed:
                          _probing || !_effectiveDraft.isComplete
                              ? null
                              : _testConnection,
                      icon: _probing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering_rounded, size: 18),
                      label: Text(AppStrings.aiHubToolsTestConnection),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saveNow,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text(AppStrings.aiConfigSave),
                    ),
                  ),
                ],
              ),
              if (_probeResult != null) ...[
                const SizedBox(height: 10),
                _probeStatusRow(context),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: aiSheetSecondaryButtonStyle(),
                      onPressed: _clearCredentials,
                      icon: const Icon(Icons.key_off_outlined, size: 18),
                      label: Text(AppStrings.aiConfigClearKeyButton),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: aiSheetSecondaryButtonStyle(),
                      onPressed: _restoreDefaults,
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: Text(AppStrings.aiConfigRestoreDefaultsButton),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: TurnaTheme.textHintColor(context),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      AppStrings.settingsAiApiConfigNotSaved,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textHintColor(context),
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Visual building blocks ────────────────────────────────────────────

  Widget _statusHero(BuildContext context) {
    final complete = _effectiveDraft.isComplete;
    final accent = complete ? TurnaTheme.brandTeal : TurnaTheme.warning;
    final subtitle = complete
        ? '${_draft.preset.label} · ${_modelChatCtrl.text.trim()}'
        : AppStrings.aiConfigStatusHintIncomplete;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.softTint(context, accent),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusXLarge),
        border: Border.all(color: TurnaTheme.glassBorder(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              complete ? Icons.check_rounded : Icons.error_outline_rounded,
              color: accent,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  complete
                      ? AppStrings.aiConfigStatusConfigured
                      : AppStrings.aiConfigStatusNotConfigured,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: TurnaTheme.textPrimaryColor(context),
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_draft.apiKey.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
              ),
              child: Text(
                _maskKey(_draft.apiKey),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _providerGrid(BuildContext context) {
    final selected = _draft.preset.id;
    return GridView.count(
      padding: EdgeInsets.zero,
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.7,
      children: [
        for (final p in providerOrder())
          _providerCard(context, p, p == selected),
      ],
    );
  }

  Widget _providerCard(
    BuildContext context,
    AiProvider provider,
    bool selected,
  ) {
    final preset = presetFor(provider);
    final v = _providerVisual(provider);
    final accent = v.color;

    return Material(
      color: selected
          ? TurnaTheme.softTint(context, accent)
          : TurnaTheme.tintLight,
      borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      child: InkWell(
        onTap: () => _onPresetChanged(provider),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            border: Border.all(
              color: selected ? accent : TurnaTheme.glassBorder(context),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
                ),
                child: Icon(v.icon, color: accent, size: 17),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preset.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: TurnaTheme.textPrimaryColor(context),
                      ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: accent, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _baseUrlBlock(BuildContext context) {
    final isCustom = _draft.preset.id == AiProvider.custom;
    if (isCustom) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _fieldLabel(context, AppStrings.settingsBaseUrlLabel),
          const SizedBox(height: 6),
          TextField(
            controller: _baseUrlCtrl,
            decoration: aiSheetInputDecoration(
              context,
              hint: AppStrings.settingsBaseUrlHint,
            ),
            onChanged: (_) => _scheduleCommit(),
          ),
          if (_baseUrlError != null) ...[
            const SizedBox(height: 6),
            Text(
              _baseUrlError!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: TurnaTheme.error),
            ),
          ],
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: TurnaTheme.tintLight,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      ),
      child: Row(
        children: [
          Icon(
            Icons.link_rounded,
            size: 16,
            color: TurnaTheme.textHintColor(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _draft.preset.baseUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modelQuickPick(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final model in _draft.preset.supportedModels)
          TurnaFilterChip(
            label: model,
            selected: _modelChatCtrl.text.trim() == model,
            onSelected: (_) {
              _modelChatCtrl.text = model;
              _scheduleCommit();
            },
          ),
      ],
    );
  }

  Widget _probeStatusRow(BuildContext context) {
    final ok = _probeResult!.ok;
    final accent = ok ? TurnaTheme.brandTeal : TurnaTheme.error;
    final text = ok
        ? AppStrings.aiHubToolsTestConnectionOk(_probeResult!.latencyMs)
        : '${AppStrings.aiHubToolsTestConnectionFail}（${_probeResult!.errorCategory}）';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: TurnaTheme.softTint(context, accent),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(color: TurnaTheme.glassBorder(context)),
      ),
      child: Row(
        children: [
          Icon(
            ok
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (!ok)
            // Copy the (sanitized) endpoint so the user can debug externally.
            IconButton(
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: AppStrings.aiConfigCopyEndpoint,
              icon: Icon(
                Icons.copy_rounded,
                size: 16,
                color: TurnaTheme.textHintColor(context),
              ),
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: _effectiveDraft.chatCompletionsUrl),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _fieldLabel(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: TurnaTheme.textSecondaryColor(context),
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

/// Surfaces credential-storage facts the user needs: session-only platforms
/// (key lost on restart) and failed migrations (plaintext kept + retry hint).
class _CredentialSafetyNotice extends StatelessWidget {
  const _CredentialSafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Selector<AiEngineConfigHolder, (AiKeyStorageKind, AiCredentialMigrationStatus)>(
      selector: (_, holder) =>
          (holder.keyStorageKind, holder.migrationStatus),
      builder: (context, state, _) {
        final (kind, migration) = state;
        if (kind == AiKeyStorageKind.unknown &&
            migration != AiCredentialMigrationStatus.failed) {
          return const SizedBox.shrink();
        }
        final isFailure = migration == AiCredentialMigrationStatus.failed;
        final isSession = kind == AiKeyStorageKind.sessionOnly;
        if (!isFailure && !isSession) return const SizedBox.shrink();

        final accent = isFailure ? TurnaTheme.error : TurnaTheme.warning;
        final message = isFailure
            ? AppStrings.aiConfigMigrationPendingNotice
            : AppStrings.aiConfigSessionKeyNotice;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: TurnaTheme.softTint(context, accent),
            borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            border: Border.all(color: TurnaTheme.glassBorder(context)),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TurnaTheme.textSecondaryColor(context),
                        height: 1.35,
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
