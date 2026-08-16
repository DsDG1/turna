// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki_official/spike/official_anki_spike_page.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/settings/widgets/settings_sound_section.dart';
import 'package:turna/views/theme.dart';

/// "高级"设置分类:Anki 深度适配的可调项(deep-adaptation plan)。
/// 影响 WebView 保真轨的 JS/解密行为 + Lite 导入阈值。改前请看底部说明。
class SettingsAdvancedSection extends StatelessWidget {
  const SettingsAdvancedSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(
          icon: Icons.enhanced_encryption_rounded,
          title: 'Anki 保真 / 解密',
        ),
        const SizedBox(height: 8),
        SettingsCard(
          children: [
            SettingsToggleTile(
              icon: Icons.flash_on_rounded,
              title: '智能去解密',
              subtitle: '首次复习跑模板 JS 解密并缓存明文,之后免 JS/联网',
              valueSelector: (p) => p.ankiPreRenderEnabled,
              onChanged: (p, v) => p.setAnkiPreRenderEnabled(v),
            ),
            settingsTileDivider(context),
            const _CaptureDelayTile(),
            settingsTileDivider(context),
            SettingsToggleTile(
              icon: Icons.lock_rounded,
              title: '强制禁用 WebView JS',
              subtitle: '永不执行模板 JS(加密牌组会显示密文)',
              valueSelector: (p) => p.ankiForceDisableJs,
              onChanged: (p, v) => p.setAnkiForceDisableJs(v),
            ),
            if (kDebugMode) ...[
              settingsTileDivider(context),
              SettingsNavigationTile(
                icon: Icons.memory_rounded,
                title: 'Official Anki Spike',
                subtitle: '加载 libturna_anki.so 并探测 ABI（仅 debug）',
                onTap: (ctx) => Navigator.of(ctx).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OfficialAnkiSpikePage(),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        SettingsSectionTitle(
          icon: Icons.layers_rounded,
          title: '导入与课程树',
        ),
        const SizedBox(height: 8),
        const SettingsCard(
          children: [
            _LiteThresholdTile(),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '智能去解密:首次复习用 WebView 跑模板 JS 解密 + 缓存明文,之后无 JS/联网。'
            '强制禁用 JS 会让加密牌组显示密文。'
            'Lite 阈值=0 表示始终建完整课程树(不切壳模式)。',
            style: TextStyle(fontSize: 12, color: TurnaTheme.textHint),
          ),
        ),
      ],
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
                    const Text('抓取延时',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(
                      'JS 跑完后等几秒抓明文(当前 ${value.round()} 秒)',
                      style:
                          TextStyle(fontSize: 12, color: TurnaTheme.textHint),
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
                    const Text('Lite 阈值',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(
                      '超过此卡数的牌组只建壳(当前 ${value.round()} 张,0=始终完整)',
                      style:
                          TextStyle(fontSize: 12, color: TurnaTheme.textHint),
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
        ],
      ),
    );
  }
}
