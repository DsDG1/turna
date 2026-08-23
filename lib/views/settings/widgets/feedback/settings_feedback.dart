// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/widgets/primitives/settings_section.dart';
import 'package:turna/views/theme.dart';

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
    final text = messageIsSelectable ? SelectableText(message) : Text(message);
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
              color: destructive ? TurnaTheme.error : TurnaTheme.brandTeal,
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
