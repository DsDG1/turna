// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/engine/ai_provider_preset.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/turna_select.dart';

/// Standalone AI API configuration page (replaces the former
/// [AiApiConfigSheet] modal). Reached from the AI Hub hero, from
/// Settings -> AI 工具 -> AI API 配置, and from the not-configured empty
/// state via the `AiApiConfigRoute` push.
///
/// Sources/writes the engine config through [AiEngineConfigHolder] (the single
/// source of truth). Edits persist live on every keystroke / toggle, so the
/// back button needs no explicit "save" - returning from the page keeps
/// whatever was typed.
///
/// Layout (top -> bottom):
///   1. Status hero card - configured / not-configured summary.
///   2. 连接 group - provider preset **cards** (replaces the dropdown) +
///      Base URL (editable only for `custom`).
///   3. 密钥与模型 group - API key (visibility toggle) + chat model (with
///      quick-pick chips from the preset) + JSON model.
///   4. 高级 group - strict-schema segmented control + cache switch + stats.
///   5. Test-connection / clear-cache action row + inline probe result.
@RoutePage()
class AiApiConfigPage extends StatefulWidget {
  const AiApiConfigPage({super.key});

  @override
  State<AiApiConfigPage> createState() => _AiApiConfigPageState();
}

class _AiApiConfigPageState extends State<AiApiConfigPage> {
  late AiEngineConfig _draft;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _modelChatCtrl;
  late final TextEditingController _modelJsonCtrl;

  AiCacheStats _stats = const AiCacheStats();
  bool _probing = false;
  bool _obscureKey = true;
  ({bool ok, int latencyMs})? _probeResult;

  @override
  void initState() {
    super.initState();
    final holder = getIt<AiEngineConfigHolder>();
    _draft = holder.config;
    _apiKeyCtrl = TextEditingController(text: _draft.apiKey);
    _baseUrlCtrl = TextEditingController(text: _draft.baseUrl);
    _modelChatCtrl = TextEditingController(text: _draft.modelChat);
    _modelJsonCtrl = TextEditingController(text: _draft.modelJson);
    _stats = getIt<AiEngine>().cacheStats();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelChatCtrl.dispose();
    _modelJsonCtrl.dispose();
    super.dispose();
  }

  void _commitDraft() {
    final holder = getIt<AiEngineConfigHolder>();
    final next = _draft.copyWith(
      apiKey: _apiKeyCtrl.text.trim(),
      customBaseUrl: _draft.preset.id == AiProvider.custom
          ? _baseUrlCtrl.text.trim()
          : null,
      modelChat: _modelChatCtrl.text.trim(),
      modelJson: _modelJsonCtrl.text.trim(),
    );
    if (next == _draft) return;
    setState(() => _draft = next);
    holder.updateConfig(next);
  }

  void _onPresetChanged(AiProvider next) {
    if (next == _draft.preset.id) return;
    final preset = presetFor(next);
    final isCustom = preset.id == AiProvider.custom;
    setState(() {
      _draft = _draft.copyWith(
        preset: preset,
        customBaseUrl: isCustom ? _draft.customBaseUrl : null,
        // copyWith drops modelChat/modelJson on a preset change so the new
        // vendor's default model wins; mirror that in the text fields.
        modelChat: null,
        modelJson: null,
        supportsReasoningOverride: preset.supportsReasoning,
      );
      _baseUrlCtrl.text = preset.baseUrl;
      _modelChatCtrl.text = preset.defaultModel;
      _modelJsonCtrl.text = preset.defaultModel;
      _probeResult = null;
    });
    getIt<AiEngineConfigHolder>().updateConfig(_draft);
  }

  Future<void> _testConnection() async {
    if (!_draft.isComplete) return;
    setState(() => _probing = true);
    try {
      final result = await getIt<AiEngine>().probeConnection(_draft);
      if (!mounted) return;
      setState(() {
        _probing = false;
        _probeResult = (ok: result.ok, latencyMs: result.latencyMs);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _probing = false;
        _probeResult = (ok: false, latencyMs: 0);
      });
    }
  }

  void _clearCache() {
    getIt<AiEngine>().clearCache();
    setState(() => _stats = getIt<AiEngine>().cacheStats());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.aiHubToolsCleared)),
    );
  }

  void _onCacheToggle(bool? next) {
    if (next == null) return;
    final updated = _draft.copyWith(cacheEnabled: next);
    setState(() => _draft = updated);
    getIt<AiEngineConfigHolder>().updateConfig(updated);
  }

  void _onStrictSchemaChanged(StrictSchemaMode next) {
    final updated = _draft.copyWith(strictSchema: next);
    setState(() => _draft = updated);
    getIt<AiEngineConfigHolder>().updateConfig(updated);
  }

  void _pickChatModel(String model) {
    _modelChatCtrl.text = model;
    _commitDraft();
  }

  static String _maskKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return '(no key)';
    if (trimmed.length <= 8) return '${trimmed[0]}…(${trimmed.length})';
    return '${trimmed.substring(0, 3)}…${trimmed.substring(trimmed.length - 4)}';
  }

  Widget _explainPrefsCard(BuildContext context) {
    return Consumer<AiExplainPrefsStore>(
      builder: (context, prefs, _) {
        return AiGroupCard(
          icon: Icons.school_outlined,
          title: AppStrings.aiPrefsSectionTitle,
          children: [
            _fieldLabel(context, AppStrings.aiPrefsReplyLanguage),
            const SizedBox(height: 8),
            TurnaSegmented<AiReplyLanguage>(
              selected: prefs.replyLanguage,
              onChanged: prefs.setReplyLanguage,
              segments: [
                ButtonSegment(
                  value: AiReplyLanguage.zh,
                  label: Text(AppStrings.aiPrefsReplyZh),
                ),
                ButtonSegment(
                  value: AiReplyLanguage.en,
                  label: Text(AppStrings.aiPrefsReplyEn),
                ),
                ButtonSegment(
                  value: AiReplyLanguage.target,
                  label: Text(AppStrings.aiPrefsReplyTarget),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _fieldLabel(context, AppStrings.aiPrefsDepth),
            const SizedBox(height: 8),
            TurnaSegmented<AiExplainDepth>(
              selected: prefs.depth,
              onChanged: prefs.setDepth,
              segments: [
                ButtonSegment(
                  value: AiExplainDepth.brief,
                  label: Text(AppStrings.aiPrefsDepthBrief),
                ),
                ButtonSegment(
                  value: AiExplainDepth.standard,
                  label: Text(AppStrings.aiPrefsDepthStandard),
                ),
                ButtonSegment(
                  value: AiExplainDepth.detailed,
                  label: Text(AppStrings.aiPrefsDepthDetailed),
                ),
              ],
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(AppStrings.aiPrefsAllowReveal),
              value: prefs.allowRevealAnswer,
              onChanged: (v) => prefs.setAllowRevealAnswer(v),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(AppStrings.aiPrefsInjectContext),
              value: prefs.injectLearnerContext,
              onChanged: (v) => prefs.setInjectLearnerContext(v),
            ),
          ],
        );
      },
    );
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
              _explainPrefsCard(context),
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
                    decoration: aiSheetInputDecoration(
                      context,
                      hint: AppStrings.settingsApiKeyHint,
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
                    onChanged: (_) => _commitDraft(),
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
                    onChanged: (_) => _commitDraft(),
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
                    onChanged: (_) => _commitDraft(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AiGroupCard(
                icon: Icons.tune_rounded,
                title: AppStrings.aiConfigGroupAdvanced,
                children: [
                  _fieldLabel(context, AppStrings.aiHubFieldStrictSchema),
                  const SizedBox(height: 8),
                  _strictSchemaChips(context),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(AppStrings.aiHubFieldCacheEnabled),
                    subtitle: Text(
                      AppStrings.aiHubFieldCacheEnabledHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    value: _draft.cacheEnabled,
                    onChanged: _onCacheToggle,
                  ),
                  const SizedBox(height: 4),
                  _cacheStatsRow(context),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: aiSheetSecondaryButtonStyle(),
                      onPressed: _probing || !_draft.isComplete
                          ? null
                          : _testConnection,
                      icon: _probing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering_rounded, size: 18),
                      label: Text(AppStrings.aiHubToolsTestConnection),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: aiSheetSecondaryButtonStyle(),
                      onPressed: _clearCache,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: Text(AppStrings.aiHubToolsClearCache),
                    ),
                  ),
                ],
              ),
              if (_probeResult != null) ...[
                const SizedBox(height: 10),
                _probeStatusRow(context),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.save_outlined,
                    size: 13,
                    color: TurnaTheme.textHintColor(context),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    AppStrings.settingsAiApiConfigNotSaved,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TurnaTheme.textHintColor(context),
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
    final complete = _draft.isComplete;
    final accent = complete ? TurnaTheme.brandTeal : TurnaTheme.warning;
    final subtitle = complete
        ? '${_draft.preset.label} · ${_draft.modelChat}'
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
          if (complete)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            onChanged: (_) => _commitDraft(),
          ),
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
            onSelected: (_) => _pickChatModel(model),
          ),
      ],
    );
  }

  Widget _probeStatusRow(BuildContext context) {
    final ok = _probeResult!.ok;
    final accent = ok ? TurnaTheme.brandTeal : TurnaTheme.error;
    final text = ok
        ? AppStrings.aiHubToolsTestConnectionOk(_probeResult!.latencyMs)
        : AppStrings.aiHubToolsTestConnectionFail;
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
        ],
      ),
    );
  }

  Widget _cacheStatsRow(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: TurnaTheme.tintLight,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      ),
      child: Row(
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 16,
            color: TurnaTheme.textHintColor(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.aiHubFieldCacheStats(
                _stats.entries,
                _stats.hits,
                _stats.misses,
                _stats.diskWrites,
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _strictSchemaChips(BuildContext context) {
    return TurnaSegmented<StrictSchemaMode>(
      selected: _draft.strictSchema,
      onChanged: _onStrictSchemaChanged,
      segments: const [
        ButtonSegment(value: StrictSchemaMode.auto, label: Text('Auto')),
        ButtonSegment(value: StrictSchemaMode.on, label: Text('On')),
        ButtonSegment(value: StrictSchemaMode.off, label: Text('Off')),
      ],
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
