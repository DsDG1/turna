// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';

Widget settingsTileDivider(BuildContext context) => Divider(
      height: 1,
      indent: 56,
      endIndent: 16,
      color: TurnaTheme.dividerBg(context),
    );

/// Shared Turna teal adaptive switch used across settings toggle tiles.
///
/// The ON state is a brand-teal track with a **white** thumb. The thumb must
/// not be tinted with the track colour: `Switch` resolves `thumbColor` before
/// it falls back to the theme default, so returning the same teal here makes
/// the thumb vanish into the track and the switch reads as one solid blob.
/// Off state is left to the platform default (white / outline thumb) so the
/// two states stay visually distinct.
Widget settingsAdaptiveSwitch({
  required bool value,
  required ValueChanged<bool>? onChanged,
}) {
  return Switch.adaptive(
    value: value,
    activeTrackColor: TurnaTheme.brandTeal,
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return TurnaTheme.textOnPrimary;
      }
      return null;
    }),
    onChanged: onChanged,
  );
}

class SettingsSectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const SettingsSectionTitle({
    super.key,
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    // 湿地雾光 R16 深页：分区标题走 sectionTitle 版面角色（19/600），
    // 图标保留为一档弱标记。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: TurnaTheme.brandTeal, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.sectionTitle(context),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  final List<Widget> children;

  /// 玻璃档位（历史参数）。湿地雾光后深页表单行族走**纸面**（ADR 0065：
  /// 实色 + 中性细边）——「一页通常只有一个玻璃对象，长列表不铺玻璃」，
  /// 参数保留只为既有调用点编译通过，不再影响渲染。
  final GlassLevel level;

  const SettingsCard({
    super.key,
    required this.children,
    this.level = GlassLevel.l1Quiet,
  });

  @override
  Widget build(BuildContext context) {
    // 纸面容器（R16）：行族的外框是排版 + 发丝线，不是玻璃卡。
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: TurnaTheme.flatPaperDecoration(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Optional override for the 40×40 icon container's icon color. Defaults
  /// to [TurnaTheme.brandTeal]. Used by diagnostic / status rows that need
  /// severity colors (success / warning / error) without rebuilding the
  /// whole container.
  final Color? iconColor;

  /// Optional override for the 40×40 icon container's tint color. Defaults
  /// to brandTeal @ 0.08 alpha. Same purpose as [iconColor] — lets status
  /// rows surface their severity while keeping the same shape.
  final Color? iconBackground;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.iconBackground,
  });

  @override
  Widget build(BuildContext context) {
    final fg = iconColor ?? TurnaTheme.brandTeal;
    // R16 深页行族：图标井 38×38 淡彩井（与 DirectoryLinkRow 同构），
    // 标题 cardTitle、副题 captionSm。
    final bg = iconBackground ?? TurnaTheme.softTint(context, fg, alpha: 0.10);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            ),
            child: Icon(
              icon,
              color: TurnaTheme.accentOnCard(context, fg),
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.cardTitle(context),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppTextStyles.captionSm(context)
                        .copyWith(fontSize: 12.5),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
      child: InkWell(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class SettingsActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final void Function(BuildContext) onTap;
  final bool enabled;
  final Color? iconColor;
  final Color? iconBackground;

  const SettingsActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.iconColor,
    this.iconBackground,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      iconColor: iconColor,
      iconBackground: iconBackground,
      onTap: enabled ? () => onTap(context) : null,
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: TurnaTheme.textHint,
      ),
    );
  }
}

class SettingsNavigationTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final void Function(BuildContext) onTap;
  final Color? iconColor;
  final Color? iconBackground;

  const SettingsNavigationTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.iconColor,
    this.iconBackground,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      iconColor: iconColor,
      iconBackground: iconBackground,
      onTap: () => onTap(context),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: TurnaTheme.textHint,
      ),
    );
  }
}
