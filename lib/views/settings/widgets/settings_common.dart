// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

Widget settingsTileDivider(BuildContext context) => Divider(
      height: 1,
      indent: 56,
      endIndent: 16,
      color: TurnaTheme.dividerBg(context),
    );

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
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: TurnaTheme.textSecondaryColor(context),
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

  const SettingsActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
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

  const SettingsNavigationTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
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
        color: TurnaTheme.textHint,
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
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
      ),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(AppStrings.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmText,
            style: const TextStyle(color: TurnaTheme.error),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Shared widgets for the Settings → 高级 sub-pages (ADR + style-unification
// pass). These wrap the same brandTeal / SettingsCard rhythm that the main
// settings list uses, so every advanced sub-page reads as the same family.
// =============================================================================

/// Visual tone for [SettingsInfoCard]. Maps to a tinted surface + accent
/// border + accent icon color. All tints are theme-aware so dark mode never
/// "贴亮块" with the legacy hard-coded hex colors.
enum SettingsInfoTone { neutral, warning, success, danger }

/// Standard scaffold used by every Settings → 高级 sub-page.
///
/// Renders the same `surfaceColor` / `elevation: 0` / `centerTitle: true`
/// AppBar that the main settings list uses (see `settings_page.dart`), so
/// the sub-pages are visually a continuation of the list rather than a
/// separate Material default AppBar. Set [allowPop] to `false` to hide
/// the back button; for pages that need to control the pop decision
/// dynamically (e.g. blocking pop until an alert is handled) wrap this
/// scaffold in a `PopScope` from the call site — same pattern the main
/// settings page uses.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.allowPop = true,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final bool allowPop;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.surfaceColor(context),
      appBar: AppBar(
        backgroundColor: TurnaTheme.surfaceColor(context),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: allowPop,
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        actions: actions,
      ),
      body: body,
    );
  }
}

/// Theme-aware info / hint banner used in place of every legacy
/// `const Card(child: Padding(child: Text(...)))` block. Each tone maps to
/// a soft tinted surface + 1px accent border; dark mode is handled inside
/// the helper so the banner never becomes a dead-bright block.
class SettingsInfoCard extends StatelessWidget {
  const SettingsInfoCard({
    super.key,
    required this.text,
    this.icon,
    this.tone = SettingsInfoTone.neutral,
  });

  final String text;
  final IconData? icon;
  final SettingsInfoTone tone;

  Color _surface(BuildContext context) {
    switch (tone) {
      case SettingsInfoTone.neutral:
        return TurnaTheme.brandTeal.withValues(alpha: 0.06);
      case SettingsInfoTone.warning:
        return TurnaTheme.warningSurface(context);
      case SettingsInfoTone.success:
        return TurnaTheme.successSurface(context);
      case SettingsInfoTone.danger:
        return TurnaTheme.dangerSurface(context);
    }
  }

  Color _accent(BuildContext context) {
    switch (tone) {
      case SettingsInfoTone.neutral:
        return TurnaTheme.brandTeal;
      case SettingsInfoTone.warning:
        return TurnaTheme.warning;
      case SettingsInfoTone.success:
        return TurnaTheme.success;
      case SettingsInfoTone.danger:
        return TurnaTheme.error;
    }
  }

  Color _text(BuildContext context) {
    switch (tone) {
      case SettingsInfoTone.neutral:
        return TurnaTheme.textPrimaryColor(context);
      case SettingsInfoTone.warning:
        return TurnaTheme.textPrimaryColor(context);
      case SettingsInfoTone.success:
        return TurnaTheme.textPrimaryColor(context);
      case SettingsInfoTone.danger:
        return TurnaTheme.textPrimaryColor(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context);
    final textColor = _text(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    height: 1.45,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact "label + value" row for stat cards (storage breakdown, cache
/// stats, FSRS preview, etc.). Lives inside a [SettingsCard] with
/// [settingsTileDivider] separators. Value text uses brandTeal w700 so it
/// reads as the primary datum in the row.
class SettingsKeyValueTile extends StatelessWidget {
  const SettingsKeyValueTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.dense = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: dense ? 8 : 12,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: TurnaTheme.brandTeal, size: 18),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TurnaTheme.brandTeal,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

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
class SettingsInfoDialog extends StatelessWidget {
  const SettingsInfoDialog({
    super.key,
    required this.title,
    required this.message,
    this.doneText,
    this.messageIsSelectable = false,
    this.maxContentWidth = 480,
  });

  final String title;
  final String message;
  final String? doneText;
  final bool messageIsSelectable;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final text = messageIsSelectable
        ? SelectableText(message)
        : Text(message);
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
      ),
      title: Text(title),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        child: text,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(doneText ?? AppStrings.commonDone),
        ),
      ],
    );
  }
}

/// Form-style dialog that wraps [SettingsConfirmDialog]'s shape +
/// button-order + radius but takes an arbitrary body for inputs. Used by
/// the deck-override editor (multiple switches + dropdowns + slider).
///
/// [destructive] flips the confirm button to [TurnaTheme.error] (default).
/// When [primaryLabel] is null, the confirm button uses the destructive
/// "保存" style: brandTeal text instead of error.
class SettingsFormDialog extends StatelessWidget {
  const SettingsFormDialog({
    super.key,
    required this.title,
    required this.body,
    this.confirmText = '保存',
    this.destructive = false,
    this.enabled = true,
  });

  final String title;
  final Widget body;
  final String confirmText;
  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
      ),
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [body],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(AppStrings.commonCancel),
        ),
        TextButton(
          onPressed: enabled ? () => Navigator.of(context).pop(true) : null,
          child: Text(
            confirmText,
            style: TextStyle(
              color: destructive
                  ? TurnaTheme.error
                  : TurnaTheme.brandTeal,
            ),
          ),
        ),
      ],
    );
  }
}

/// Primary CTA style for the Settings → 高级 sub-pages. Renders a teal
/// filled button with the standard radius — used in place of the legacy
/// `FilledButton.tonalIcon` (which is a different shade on every platform)
/// and the default `FilledButton` (which is primary container, not
/// brandTeal). Mirrors the main settings page's teal CTA rhythm.
class SettingsPrimaryButton extends StatelessWidget {
  const SettingsPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: TurnaTheme.brandTeal,
      foregroundColor: Colors.white,
      disabledBackgroundColor: TurnaTheme.brandTeal.withValues(alpha: 0.35),
      disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      ),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
    if (icon != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: style,
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: style,
      child: Text(label),
    );
  }
}

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
class SettingsSegmentedBarItem {
  const SettingsSegmentedBarItem({
    required this.label,
    required this.value,
    required this.color,
    this.formattedValue,
  });

  final String label;
  final double value;
  final Color color;
  final String? formattedValue;
}

/// Multi-color segmented distribution bar (e.g. storage breakdown, memory distribution).
class SettingsSegmentedBar extends StatelessWidget {
  const SettingsSegmentedBar({
    super.key,
    required this.segments,
    this.height = 10,
    this.showLegend = true,
  });

  final List<SettingsSegmentedBarItem> segments;
  final double height;
  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (sum, s) => sum + s.value);
    final hasData = total > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(height / 2),
            child: Container(
              height: height,
              color: TurnaTheme.dividerBg(context),
              child: hasData
                  ? Row(
                      children: [
                        for (final s in segments)
                          if (s.value > 0)
                            Expanded(
                              flex: (s.value / total * 1000).round().clamp(1, 1000),
                              child: Container(color: s.color),
                            ),
                      ],
                    )
                  : const SizedBox.expand(),
            ),
          ),
          if (showLegend && hasData) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final s in segments)
                  if (s.value > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: s.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          s.label,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: TurnaTheme.textSecondaryColor(context),
                              ),
                        ),
                        if (s.formattedValue != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            s.formattedValue!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: TurnaTheme.textPrimaryColor(context),
                                ),
                          ),
                        ],
                      ],
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Standard empty card used inside settings sub-pages when lists are empty.
class SettingsEmptyCard extends StatelessWidget {
  const SettingsEmptyCard({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: TurnaTheme.brandTeal,
                  size: 24,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TurnaTheme.textHintColor(context),
                    ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: onAction,
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(
                      color: TurnaTheme.brandTeal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact status pill/badge for list tiles and cards.
class SettingsStatusPill extends StatelessWidget {
  const SettingsStatusPill({
    super.key,
    required this.text,
    this.tone = SettingsInfoTone.neutral,
    this.icon,
  });

  final String text;
  final SettingsInfoTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    Color border;

    switch (tone) {
      case SettingsInfoTone.neutral:
        bg = TurnaTheme.brandTeal.withValues(alpha: 0.08);
        fg = TurnaTheme.brandTeal;
        border = TurnaTheme.brandTeal.withValues(alpha: 0.25);
        break;
      case SettingsInfoTone.success:
        bg = TurnaTheme.successSurface(context);
        fg = TurnaTheme.success;
        border = TurnaTheme.success.withValues(alpha: 0.35);
        break;
      case SettingsInfoTone.warning:
        bg = TurnaTheme.warningSurface(context);
        fg = TurnaTheme.warning;
        border = TurnaTheme.warning.withValues(alpha: 0.35);
        break;
      case SettingsInfoTone.danger:
        bg = TurnaTheme.dangerSurface(context);
        fg = TurnaTheme.error;
        border = TurnaTheme.error.withValues(alpha: 0.35);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: fg, size: 13),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

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
            color: enabled ? TurnaTheme.brandTeal : TurnaTheme.textHintColor(context),
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

