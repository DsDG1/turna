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

/// AI configuration sheet (Phase 2.4 rewrite; 视觉重构版).
///
/// Sources/writes the engine config through [AiEngineConfigHolder] (the single
/// source of truth established in Phase 4.5), not the legacy `AiCourseProvider`.
/// The provider adapter (`AiCourseProvider.updateConfig`) is preserved as a
/// back-compat shim — see `ai_course_provider.dart`.
///
/// Layout (top to bottom):
///   1. Drag handle + header（渐变图标 + 标题 + 「不保存到本地」提示 + 关闭钮）。
///   2. 「连接」分组卡：preset 下拉 + Base URL（仅 custom 可编辑）。
///   3. 「密钥与模型」分组卡：API key（可切换可见性；仅内存，不持久化）+
///      聊天模型 + JSON 模型。
///   4. 「高级」分组卡：strict schema 分段控件 + 缓存开关 + 缓存统计。
///   5. 测试连接 / 清缓存 双钮 + 全宽保存钮。
///
/// 高度上限 = 屏高 - 状态栏高度 - 顶部留白，保证 isScrollControlled 全高
/// 展开（尤其键盘弹出）时内容不会顶进状态栏。
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
  bool _obscureKey = true;

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

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isCustom = _draft.preset.id == AiProvider.custom;
    final media = MediaQuery.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        // 上限避开状态栏：屏高 - 状态栏 - 顶部 12 留白。
        maxHeight: media.size.height - media.padding.top - 12,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 10,
          bottom: media.viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dragHandle(context),
            const SizedBox(height: 14),
            _header(context),
            const SizedBox(height: 18),
            _groupCard(
              context,
              icon: Icons.hub_rounded,
              title: AppStrings.aiConfigGroupConnection,
              children: [
                _fieldLabel(context, AppStrings.aiHubFieldPreset),
                const SizedBox(height: 6),
                DropdownButtonFormField<AiProvider>(
                  initialValue: _draft.preset.id,
                  isExpanded: true,
                  dropdownColor: VarnamalaTheme.elevatedCardBg(context),
                  decoration: _fieldDecoration(context),
                  items: [
                    for (final p in providerOrder())
                      DropdownMenuItem<AiProvider>(
                        value: p,
                        child: Text(presetFor(p).label),
                      ),
                  ],
                  onChanged: _onPresetChanged,
                ),
                const SizedBox(height: 12),
                _fieldLabel(context, AppStrings.settingsBaseUrlLabel),
                const SizedBox(height: 6),
                TextField(
                  controller: _baseUrlCtrl,
                  enabled: isCustom,
                  decoration: _fieldDecoration(
                    context,
                    hint: AppStrings.settingsBaseUrlHint,
                  ),
                  onChanged: (_) => _commitDraft(),
                ),
                if (!isCustom) ...[
                  const SizedBox(height: 6),
                  Text(
                    AppStrings.aiHubFieldBaseUrlHintPreset,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: VarnamalaTheme.textHintColor(context),
                        ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _groupCard(
              context,
              icon: Icons.key_rounded,
              title: AppStrings.aiConfigGroupModels,
              children: [
                _fieldLabel(context, AppStrings.settingsApiKeyLabel),
                const SizedBox(height: 6),
                TextField(
                  controller: _apiKeyCtrl,
                  obscureText: _obscureKey,
                  decoration: _fieldDecoration(
                    context,
                    hint: AppStrings.settingsApiKeyHint,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: VarnamalaTheme.textHintColor(context),
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
                  decoration: _fieldDecoration(
                    context,
                    hint: AppStrings.settingsModelHint,
                  ),
                  onChanged: (_) => _commitDraft(),
                ),
                const SizedBox(height: 12),
                _fieldLabel(context, AppStrings.aiHubFieldModelJson),
                const SizedBox(height: 6),
                TextField(
                  controller: _modelJsonCtrl,
                  decoration: _fieldDecoration(
                    context,
                    hint: AppStrings.settingsModelHint,
                  ),
                  onChanged: (_) => _commitDraft(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _groupCard(
              context,
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
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          VarnamalaTheme.radiusMedium,
                        ),
                      ),
                      side: BorderSide(
                        color: VarnamalaTheme.peacockTeal
                            .withValues(alpha: 0.5),
                      ),
                    ),
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
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          VarnamalaTheme.radiusMedium,
                        ),
                      ),
                      side: BorderSide(
                        color: VarnamalaTheme.peacockTeal
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    onPressed: _clearCache,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: Text(AppStrings.aiHubToolsClearCache),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    VarnamalaTheme.radiusLarge,
                  ),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: () {
                _commitDraft();
                Navigator.of(context).maybePop();
              },
              icon: const Icon(Icons.check_rounded),
              label: Text(AppStrings.settingsSaveConfig),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Visual building blocks ────────────────────────────────────────────

  Widget _dragHandle(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: VarnamalaTheme.textHint.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusRound),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                VarnamalaTheme.amethystLeague,
                VarnamalaTheme.peacockTeal,
              ],
            ),
            borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.settingsAiApiConfigSheetTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 12,
                    color: VarnamalaTheme.textHintColor(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      AppStrings.settingsAiApiConfigNotSaved,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: VarnamalaTheme.textHintColor(context),
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: VarnamalaTheme.tintLight,
          shape: const CircleBorder(),
          child: IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: AppStrings.commonClose,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ],
    );
  }

  /// 分组卡：softTint 底 + 白色高光细边 + 圆角 20，与练习页 SoftCard 同一
  /// 设计语言但更轻（无外层光晕，避免在 sheet 内叠影过重）。
  Widget _groupCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    final accent =
        VarnamalaTheme.accentOnCard(context, VarnamalaTheme.peacockTeal);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VarnamalaTheme.softTint(context, VarnamalaTheme.peacockTeal),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusXLarge - 4),
        border: Border.all(
          color: VarnamalaTheme.glassBorder(context),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: VarnamalaTheme.textPrimaryColor(context),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _fieldLabel(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: VarnamalaTheme.textSecondaryColor(context),
            fontWeight: FontWeight.w600,
          ),
    );
  }

  /// 统一输入框样式：tint 填充 + 圆角 12 无硬描边，聚焦时出 teal 细边。
  InputDecoration _fieldDecoration(
    BuildContext context, {
    String? hint,
    Widget? suffixIcon,
  }) {
    final base = OutlineInputBorder(
      borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: VarnamalaTheme.textHintColor(context)),
      filled: true,
      fillColor: VarnamalaTheme.tintLight,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      suffixIcon: suffixIcon,
      border: base,
      enabledBorder: base,
      disabledBorder: base,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        borderSide: const BorderSide(
          color: VarnamalaTheme.peacockTeal,
          width: 1.2,
        ),
      ),
    );
  }

  Widget _strictSchemaChips(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<StrictSchemaMode>(
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
      ),
    );
  }

  Widget _cacheStatsRow(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: VarnamalaTheme.tintLight,
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      ),
      child: Row(
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 16,
            color: VarnamalaTheme.textHintColor(context),
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
}
