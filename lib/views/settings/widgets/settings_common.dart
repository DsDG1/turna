// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/views/theme.dart';

Widget settingsTileDivider(BuildContext context) => Divider(
      height: 1,
      indent: 56,
      endIndent: 16,
      color: VarnamalaTheme.dividerBg(context),
    );

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
          Icon(icon, color: VarnamalaTheme.peacockTeal, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: VarnamalaTheme.textSecondaryColor(context),
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
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
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

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
            ),
            child: Icon(
              icon,
              color: VarnamalaTheme.peacockTeal,
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
                          color: VarnamalaTheme.textHintColor(context),
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
      borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
      child: InkWell(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
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

  const SettingsActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => onTap(context),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: VarnamalaTheme.textHint,
      ),
    );
  }
}

class SettingsNavigationTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final void Function(BuildContext) onTap;

  const SettingsNavigationTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: icon,
      title: title,
      onTap: () => onTap(context),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: VarnamalaTheme.textHint,
      ),
    );
  }
}

class SettingsConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;

  const SettingsConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmText,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
      ),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmText,
            style: const TextStyle(color: VarnamalaTheme.error),
          ),
        ),
      ],
    );
  }
}
