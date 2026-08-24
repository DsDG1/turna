// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/views/theme.dart';

Widget settingsTileDivider(BuildContext context) => Divider(
      height: 1,
      indent: 56,
      endIndent: 16,
      color: TurnaTheme.dividerBg(context),
    );

/// Shared Turna teal adaptive switch used across settings toggle tiles.

/// Shared Turna teal adaptive switch used across settings toggle tiles.
Widget settingsAdaptiveSwitch({
  required bool value,
  required ValueChanged<bool>? onChanged,
}) {
  return Switch.adaptive(
    value: value,
    activeTrackColor: TurnaTheme.brandTeal,
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return TurnaTheme.brandTeal;
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: TurnaTheme.brandTeal, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const SettingsCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
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
    final bg = iconBackground ?? TurnaTheme.brandTeal.withValues(alpha: 0.08);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            ),
            child: Icon(
              icon,
              color: fg,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TurnaTheme.textHintColor(context),
                        ),
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
