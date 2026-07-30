// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/ai/engine/ai_cache.dart';
import 'package:varnamala/application/ai/engine/ai_engine.dart';
import 'package:varnamala/application/ai/engine/ai_engine_config.dart';
import 'package:varnamala/application/ai/engine/ai_engine_config_holder.dart';
import 'package:varnamala/application/ai/engine/ai_provider_preset.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/theme.dart';

/// AI configuration sheet (Phase 2.4 rewrite).
///
/// Sources/writes the engine config through [AiEngineConfigHolder] (the single
/// source of truth established in Phase 4.5), not the legacy `AiCourseProvider`.
/// The provider adapter (`AiCourseProvider.updateConfig`) is preserved as a
/// back-compat shim — see `ai_course_provider.dart`.
///
/// Layout (top to bottom):
///   1. Preset dropdown (deepseek / openai / moonshot / ollama / custom).
///      Picking a named preset fills Base URL + default model + reasoning flag.
///   2. API key (obscure text; in-memory only; never persisted).
///   3. Custom Base URL — shown only for the `custom` preset.
///   4. Model for chat / Model for JSON (free-text).
///   5. Strict schema segmented control (Auto / On / Off).
///   6. Cache enabled switch.
///   7. Cache stats row (live from [AiEngine.cacheStats]).
///   8. Test connection button + clear cache button.
///
/// The 「不保存到本地」 banner is retained — the security stance is unchanged.
class AiApiConfigSheet extends StatefulWidget {
  final AiCourseProvider provider;

  const AiApiConfigSheet({required this.provider, super.key});

  @override
  State<AiApiConfigSheet> createState() => _AiApiConfigSheetState();
}

class _AiApiConfigSheetState extends State<AiApiConfigSheet> {
  late AiEngineConfig _draft;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _modelChatCtrl;
  late final TextEditingController _modelJsonCtrl;

  AiCacheStats _stats = const AiCacheStats();
  bool _probing = false;

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

  void _onPresetChanged(AiProvider? next) {
    if (next == null) return;
    final preset = presetFor(next);
    final isCustom = preset.id == AiProvider.custom;
    setState(() {
      _draft = _draft.copyWith(
        preset: preset,
        customBaseUrl: isCustom ? _draft.customBaseUrl : null,
        // The copyWith drops modelChat/modelJson when the preset changed (so the
        // user re-picks a model valid for the new vendor); reflect that in the
        // text fields too.
        modelChat: null,
        modelJson: null,
        supportsReasoningOverride: preset.supportsReasoning,
      );
      _baseUrlCtrl.text = preset.baseUrl;
      _modelChatCtrl.text = preset.defaultModel;
      _modelJsonCtrl.text = preset.defaultModel;
    });
    _commitDraft();
  }

  Future<void> _testConnection() async {
    if (!_draft.isComplete) return;
    setState(() => _probing = true);
    try {
      final result = await getIt<AiEngine>().probeConnection(_draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.ok
                ? AppStrings.aiHubToolsTestConnectionOk(result.latencyMs)
                : AppStrings.aiHubToolsTestConnectionFail,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.aiHubToolsTestConnectionFail)),
      );
    } finally {
      if (mounted) setState(() => _probing = false);
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

  @override
  Widget build(BuildContext context) {
    final isCustom = _draft.preset.id == AiProvider.custom;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context),
            const SizedBox(height: 4),
            Text(
              AppStrings.settingsAiApiConfigNotSaved,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: VarnamalaTheme.textHintColor(context),
                  ),
            ),
            const SizedBox(height: 12),
            _section(context, AppStrings.aiHubFieldPreset,
                child: DropdownButtonFormField<AiProvider>(
                  initialValue: _draft.preset.id,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final p in providerOrder())
                      DropdownMenuItem<AiProvider>(
                        value: p,
                        child: Text(presetFor(p).label),
                      ),
                  ],
                  onChanged: _onPresetChanged,
                )),
            const SizedBox(height: 8),
            _section(context, AppStrings.settingsApiKeyLabel,
                child: TextField(
                  controller: _apiKeyCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: AppStrings.settingsApiKeyHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _commitDraft(),
                )),
            const SizedBox(height: 8),
            _section(
              context,
              AppStrings.settingsBaseUrlLabel,
              child: TextField(
                controller: _baseUrlCtrl,
                enabled: isCustom,
                decoration: InputDecoration(
                  hintText: AppStrings.settingsBaseUrlHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: isCustom
                      ? null
                      : AppStrings.aiHubFieldBaseUrlHintPreset,
                ),
                onChanged: (_) => _commitDraft(),
              ),
            ),
            const SizedBox(height: 8),
            _section(context, AppStrings.aiHubFieldModelChat,
                child: TextField(
                  controller: _modelChatCtrl,
                  decoration: InputDecoration(
                    hintText: AppStrings.settingsModelHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _commitDraft(),
                )),
            const SizedBox(height: 8),
            _section(context, AppStrings.aiHubFieldModelJson,
                child: TextField(
                  controller: _modelJsonCtrl,
                  decoration: InputDecoration(
                    hintText: AppStrings.settingsModelHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _commitDraft(),
                )),
            const SizedBox(height: 8),
            _section(context, AppStrings.aiHubFieldStrictSchema, child: _strictSchemaChips(context)),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _probing ? null : _testConnection,
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
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _clearCache,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: Text(AppStrings.aiHubToolsClearCache),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  _commitDraft();
                  Navigator.of(context).maybePop();
                },
                icon: const Icon(Icons.check),
                label: Text(AppStrings.settingsSaveConfig),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String label, {required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: VarnamalaTheme.peacockTeal,
                  fontWeight: FontWeight.w600,
                )),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  Widget _strictSchemaChips(BuildContext context) {
    return SegmentedButton<StrictSchemaMode>(
      segments: const [
        ButtonSegment(value: StrictSchemaMode.auto, label: Text('Auto')),
        ButtonSegment(value: StrictSchemaMode.on, label: Text('On')),
        ButtonSegment(value: StrictSchemaMode.off, label: Text('Off')),
      ],
      selected: {_draft.strictSchema},
      onSelectionChanged: (set) {
        if (set.isEmpty) return;
        _onStrictSchemaChanged(set.first);
      },
    );
  }

  Widget _cacheStatsRow(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      ),
      child: Row(
        children: [
          const Icon(Icons.analytics_outlined, size: 16),
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

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Text(
          AppStrings.settingsAiApiConfigSheetTitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, size: 22),
          tooltip: AppStrings.commonClose,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}