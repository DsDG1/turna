// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/settings/widgets/settings_sound_section.dart'
    show SettingsToggleTile;
import 'package:turna/views/theme.dart';

/// "高级" category (Plan 2 §6): a stable cross-feature hub with four
/// first-level entries — AI 连接 / 存储与性能 / 系统健康与诊断 / 旧版与兼容性.
/// The former Anki deep-adaptation tunables moved into the second-level
/// [SettingsLegacyCompatibilityPage]. No internal engine/implementation
/// jargon on the hub itself.
class SettingsAdvancedSection extends StatelessWidget {
  const SettingsAdvancedSection({
    super.key,
    this.showLegacy = false,
    this.onOpenLegacy,
  });

  /// When true the section renders the second-level 旧版与兼容性 page instead
  /// of the hub list. The Settings page owns this flag so external
  /// [SettingsNavRequest]s with the `legacyCompatibility` anchor land here.
  final bool showLegacy;

  /// Invoked when the hub's 旧版与兼容性 entry is tapped; the owning page
  /// flips its anchor so the app-bar title follows the second-level page.
  final VoidCallback? onOpenLegacy;

  @override
  Widget build(BuildContext context) {
    if (showLegacy) {
      return const _LegacyCompatibilityBody();
    }
    return _AdvancedHubBody(onOpenLegacy: onOpenLegacy);
  }
}

class _AdvancedHubBody extends StatelessWidget {
  const _AdvancedHubBody({this.onOpenLegacy});

  final VoidCallback? onOpenLegacy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            AppStrings.settingsAdvancedIntroBanner,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                  height: 1.4,
                ),
          ),
        ),
        SettingsCard(
          children: [
            SettingsNavigationTile(
              icon: Icons.hub_rounded,
              title: AppStrings.settingsAdvancedAiConnectionTitle,
              subtitle: AppStrings.settingsAdvancedAiConnectionSubtitle,
              onTap: (ctx) => ctx.router.push(const AiApiConfigRoute()),
            ),
            settingsTileDivider(context),
            SettingsNavigationTile(
              icon: Icons.sd_storage_outlined,
              title: AppStrings.settingsAdvancedStorageTitle,
              subtitle: AppStrings.settingsAdvancedStorageSubtitle,
              onTap: (ctx) =>
                  ctx.router.push(StorageDiagnosticsRoute()),
            ),
            settingsTileDivider(context),
            SettingsNavigationTile(
              icon: Icons.monitor_heart_outlined,
              title: AppStrings.settingsAdvancedSystemHealthTitle,
              subtitle: AppStrings.settingsAdvancedSystemHealthSubtitle,
              onTap: (ctx) => ctx.router.push(const SystemHealthRoute()),
            ),
            settingsTileDivider(context),
            SettingsNavigationTile(
              icon: Icons.history_rounded,
              title: AppStrings.settingsAdvancedLegacyTitle,
              subtitle: AppStrings.settingsAdvancedLegacySubtitle,
              onTap: (_) => onOpenLegacy?.call(),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Second-level 旧版与兼容性 page (Plan 2 §6.6): former advanced-section
/// Anki tunables, each annotated with 适用症状 / 副作用 / 默认值 / 重启需求,
/// plus a one-tap restore-defaults action that never deletes user data.
class _LegacyCompatibilityBody extends StatelessWidget {
  const _LegacyCompatibilityBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(
          icon: Icons.smart_display_rounded,
          title: AppStrings.settingsLegacySectionDisplayTitle,
        ),
        const SizedBox(height: 8),
        SettingsCard(
          children: [
            SettingsToggleTile(
              icon: Icons.flash_on_rounded,
              title: AppStrings.settingsLegacyDecryptTitle,
              subtitle: AppStrings.settingsLegacyDecryptSubtitle,
              valueSelector: (p) => p.ankiPreRenderEnabled,
              onChanged: (p, v) => p.setAnkiPreRenderEnabled(v),
            ),
            settingsTileDivider(context),
            const _CaptureDelayTile(),
            settingsTileDivider(context),
            SettingsToggleTile(
              icon: Icons.lock_rounded,
              title: AppStrings.settingsLegacyForceDisableJsTitle,
              subtitle: AppStrings.settingsLegacyForceDisableJsSubtitle,
              valueSelector: (p) => p.ankiForceDisableJs,
              onChanged: (p, v) => p.setAnkiForceDisableJs(v),
            ),
            settingsTileDivider(context),
            const _LiteThresholdTile(),
          ],
        ),
        const SizedBox(height: 20),
        SettingsSectionTitle(
          icon: Icons.science_rounded,
          title: '实验性兼容开关',
        ),
        const SizedBox(height: 8),
        const _AiEngineTunablesCard(),
        const SizedBox(height: 20),
        SettingsSectionTitle(
          icon: Icons.restart_alt_rounded,
          title: AppStrings.settingsLegacyResetDefaultsTitle,
        ),
        const SizedBox(height: 8),
        SettingsCard(
          children: [
            SettingsActionTile(
              icon: Icons.restore_rounded,
              title: AppStrings.settingsLegacyResetDefaultsTitle,
              subtitle: AppStrings.settingsLegacyResetDefaultsSubtitle,
              onTap: (context) => _confirmResetDefaults(context),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _confirmResetDefaults(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettingsConfirmDialog(
        title: AppStrings.settingsLegacyResetDefaultsTitle,
        message: AppStrings.settingsLegacyResetDefaultsSubtitle,
        confirmText: AppStrings.settingsLegacyResetDefaultsConfirm,
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<SettingsProvider>().resetLegacyCompatibilityDefaults();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.settingsLegacyResetDefaultsDone)),
      );
    }
  }
}

/// Strict-schema policy and the AI response-cache master toggle — engine-level
/// switches that used to clutter the AI connection page (Plan 2 §6.2: "strict
/// schema、缓存调试和统计不在普通 AI 连接页，放诊断或旧版页").
class _AiEngineTunablesCard extends StatefulWidget {
  const _AiEngineTunablesCard();

  @override
  State<_AiEngineTunablesCard> createState() => _AiEngineTunablesCardState();
}

class _AiEngineTunablesCardState extends State<_AiEngineTunablesCard> {
  @override
  Widget build(BuildContext context) {
    // The holder is app-scoped (injectable); tests that never set up DI skip
    // this card rather than crash the whole settings tree.
    if (!getIt.isRegistered<AiEngineConfigHolder>()) {
      return const SizedBox.shrink();
    }
    final holder = getIt<AiEngineConfigHolder>();
    return ListenableBuilder(
      listenable: holder,
      builder: (context, _) {
        final config = holder.config;
        return SettingsCard(
          children: [
            SettingsTile(
              icon: Icons.cached_rounded,
              title: 'AI 响应缓存',
              subtitle: '命中相同请求时直接复用结果；关闭后每次都重新请求',
              trailing: settingsAdaptiveSwitch(
                value: config.cacheEnabled,
                onChanged: (v) => holder.updateConfig(
                  config.copyWith(cacheEnabled: v),
                ),
              ),
            ),
            settingsTileDivider(context),
            SettingsActionTile(
              icon: Icons.verified_outlined,
              title: 'Strict JSON 模式',
              subtitle: '当前：${config.strictSchema.name}'
                  '（auto=自动回退，on=强制，off=宽松）',
              onTap: (context) {
                final next = switch (config.strictSchema) {
                  StrictSchemaMode.auto => StrictSchemaMode.on,
                  StrictSchemaMode.on => StrictSchemaMode.off,
                  StrictSchemaMode.off => StrictSchemaMode.auto,
                };
                holder.updateConfig(config.copyWith(strictSchema: next));
              },
            ),
          ],
        );
      },
    );
  }
}

/// 抓取延时滑块(1-10 秒)。拖动时用本地状态,松手才写 prefs。
class _CaptureDelayTile extends StatefulWidget {
  const _CaptureDelayTile();

  @override
  State<_CaptureDelayTile> createState() => _CaptureDelayTileState();
}

class _CaptureDelayTileState extends State<_CaptureDelayTile> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final persisted =
        context.select<SettingsProvider, int>((p) => p.ankiCaptureDelaySec);
    final value = _drag ?? persisted.toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: const Icon(Icons.timer_outlined,
                    color: TurnaTheme.brandTeal, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.settingsLegacyCaptureDelayTitle,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    Text(
                      '${value.round()} 秒',
                      style: const TextStyle(
                          fontSize: 12, color: TurnaTheme.textHint),
                    ),
                  ],
                ),
              ),
              Text('${value.round()}s',
                  style: const TextStyle(
                      color: TurnaTheme.brandTeal,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: value,
            min: 1,
            max: 10,
            divisions: 9,
            activeColor: TurnaTheme.brandTeal,
            label: '${value.round()}s',
            onChanged: (v) => setState(() => _drag = v),
            onChangeEnd: (v) {
              _drag = null;
              context
                  .read<SettingsProvider>()
                  .setAnkiCaptureDelaySec(v.round());
            },
          ),
          Text(
            AppStrings.settingsLegacyCaptureDelaySubtitle,
            style: const TextStyle(fontSize: 11, color: TurnaTheme.textHint),
          ),
        ],
      ),
    );
  }
}

/// Lite 阈值滑块(0-10000 张)。0 = 始终完整课程树。
class _LiteThresholdTile extends StatefulWidget {
  const _LiteThresholdTile();

  @override
  State<_LiteThresholdTile> createState() => _LiteThresholdTileState();
}

class _LiteThresholdTileState extends State<_LiteThresholdTile> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final persisted =
        context.select<SettingsProvider, int>((p) => p.ankiLiteThreshold);
    final value = _drag ?? persisted.toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: const Icon(Icons.layers_rounded,
                    color: TurnaTheme.brandTeal, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.settingsLegacyLiteThresholdTitle,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    Text(
                      value.round() == 0
                          ? '始终完整课程树'
                          : '超过 ${value.round()} 张只建壳',
                      style: const TextStyle(
                          fontSize: 12, color: TurnaTheme.textHint),
                    ),
                  ],
                ),
              ),
              Text(
                value.round() == 0 ? '关' : '${value.round()}',
                style: const TextStyle(
                    color: TurnaTheme.brandTeal, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Slider(
            value: value,
            min: 0,
            max: 10000,
            divisions: 100,
            activeColor: TurnaTheme.brandTeal,
            onChanged: (v) => setState(() => _drag = v),
            onChangeEnd: (v) {
              _drag = null;
              context.read<SettingsProvider>().setAnkiLiteThreshold(v.round());
            },
          ),
          Text(
            AppStrings.settingsLegacyLiteThresholdSubtitle,
            style: const TextStyle(fontSize: 11, color: TurnaTheme.textHint),
          ),
        ],
      ),
    );
  }
}

// Official-Anki internal import diagnostics moved out of the formal Advanced
// hub (Plan 2 §4.6): it is a duplicate/dangerous import path that conflicts
// with the unified import flow. Debug-only access now lives in the developer
// lab category (settings_page.dart), gated by kDebugMode.
