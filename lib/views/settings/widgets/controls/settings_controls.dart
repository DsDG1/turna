// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/views/settings/widgets/primitives/settings_section.dart';
import 'package:turna/views/theme.dart';

/// Generic version of [SettingsToggleTile] for sources other than
/// [SettingsProvider] (e.g. [SystemHealthMonitor.safeMode]). Same visual
/// rhythm: 40×40 brandTeal-tint icon container + bodyLarge w600 title +
/// bodySmall hint subtitle + teal Switch on the right.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: settingsAdaptiveSwitch(
        value: enabled && value,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

/// Non-destructive info / result dialog used in place of the bare
/// `AlertDialog(actions: [TextButton(知道了)])` pattern. Same shape as
/// [SettingsConfirmDialog] so the dialog family reads consistently.

/// Compact form-row used inside [SettingsFormDialog] and inline list
/// editors. Renders a label on the left and a trailing widget (Switch,
/// Dropdown, Slider value, etc.) on the right. Vertical padding matches
/// the main settings list so form-in-dialog feels native.
class SettingsFormRow extends StatelessWidget {
  const SettingsFormRow({
    super.key,
    required this.label,
    required this.trailing,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

/// Reusable info-row used in dialog content. Renders a [label] on the left
/// and a [value] on the right, both bodyMedium, with a thin top divider
/// so consecutive rows stack into a clean key/value list.

/// Reusable info-row used in dialog content. Renders a [label] on the left
/// and a [value] on the right, both bodyMedium, with a thin top divider
/// so consecutive rows stack into a clean key/value list.
class SettingsInfoRow extends StatelessWidget {
  const SettingsInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.textPrimaryColor(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single segment in [SettingsSegmentedBar].

/// Turna-styled form dropdown with rounded border and subtle background.
class SettingsFormDropdown<T> extends StatelessWidget {
  const SettingsFormDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: enabled
            ? TurnaTheme.brandTeal.withValues(alpha: 0.05)
            : TurnaTheme.dividerBg(context).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: enabled
              ? TurnaTheme.brandTeal.withValues(alpha: 0.25)
              : TurnaTheme.statCardBorder(context),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          icon: Icon(
            Icons.expand_more_rounded,
            color: enabled
                ? TurnaTheme.brandTeal
                : TurnaTheme.textHintColor(context),
            size: 18,
          ),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: enabled
                    ? TurnaTheme.textPrimaryColor(context)
                    : TurnaTheme.textHintColor(context),
              ),
          items: items,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

/// The ONE provider-bound switch tile (Plan §14.3): value comes from a
/// narrow [context.select] on the owning provider, writes go through the
/// injected callback. The former SettingsToggleTile / AccessibilityToggleTile
/// / FunToggleTile variants were structurally identical apart from the
/// provider type — they now delegate here.
class ProviderBoundToggleTile<T extends ChangeNotifier>
    extends StatelessWidget {
  const ProviderBoundToggleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.valueSelector,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool Function(T) valueSelector;
  final void Function(T, bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final value = context.select<T, bool>(valueSelector);
    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: settingsAdaptiveSwitch(
        value: value,
        onChanged: (newValue) => onChanged(context.read<T>(), newValue),
      ),
    );
  }
}
