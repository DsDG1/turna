// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/components/primitives/settings_section.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_sheet.dart';
import 'package:turna/views/widgets/turna_top_bar.dart';

/// Visual tone for [SettingsInfoCard]. Maps to a tinted surface + accent
/// border + accent icon color. All tints are theme-aware so dark mode never
/// "贴亮块" with the legacy hard-coded hex colors.
enum SettingsInfoTone { neutral, warning, success, danger }

/// Standard scaffold used by every Settings → 高级 sub-page.
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
      appBar: TurnaTopBar(
        title: title,
        centerTitle: true,
        automaticallyImplyLeading: allowPop,
        actions: actions,
        showDivider: true,
      ),
      body: body,
    );
  }
}

/// Theme-aware info / hint banner used in place of every legacy
/// `const Card(child: Padding(child: Text(...)))` block.
class SettingsInfoCard extends StatelessWidget {
  const SettingsInfoCard({
    super.key,
    required this.text,
    this.icon,
    this.iconId,
    this.tone = SettingsInfoTone.neutral,
  });

  final String text;
  final IconData? icon;
  final TurnaIconId? iconId;
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

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context);
    final textColor = TurnaTheme.textPrimaryColor(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(
        color: _surface(context),
        borderRadius: TurnaTheme.borderRadius,
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (iconId != null) ...[
            TurnaIcon(iconId!, color: accent, size: 20),
            const SizedBox(width: AppSpacing.md),
          ] else if (icon != null) ...[
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyText(context).copyWith(color: textColor),
            ),
          ),
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
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyText(context)
                    .copyWith(color: TurnaTheme.textHintColor(context)),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.lg),
                TextButton(
                  onPressed: onAction,
                  child: Text(
                    actionLabel!,
                    style: AppTextStyles.captionSm(context).copyWith(
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

/// Compact 4px status badge for list tiles and cards.
class SettingsStatusPill extends StatelessWidget {
  const SettingsStatusPill({
    super.key,
    required this.text,
    this.tone = SettingsInfoTone.neutral,
    this.icon,
    this.iconId,
  });

  final String text;
  final SettingsInfoTone tone;
  final IconData? icon;
  final TurnaIconId? iconId;

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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: TurnaTheme.borderRadius,
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconId != null) ...[
            TurnaIcon(iconId!, color: fg, size: 13),
            const SizedBox(width: AppSpacing.xs),
          ] else if (icon != null) ...[
            Icon(icon, color: fg, size: 13),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            text,
            style: AppTextStyles.captionSm(context)
                .copyWith(fontWeight: FontWeight.w600, color: fg),
          ),
        ],
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
    return TurnaDialogPanel(
      title: title,
      body: Text(
        message,
        style: AppTextStyles.bodyText(context)
            .copyWith(color: TurnaTheme.textSecondaryColor(context)),
      ),
      actions: [
        TurnaSheetAction(
          label: AppStrings.commonCancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        TurnaSheetAction(
          label: confirmText,
          primary: true,
          destructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

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
    final style = AppTextStyles.bodyText(context)
        .copyWith(color: TurnaTheme.textSecondaryColor(context));
    final text = messageIsSelectable
        ? SelectableText(message, style: style)
        : Text(message, style: style);
    return TurnaDialogPanel(
      title: title,
      maxWidth: maxContentWidth,
      body: text,
      actions: [
        TurnaSheetAction(
          label: doneText ?? AppStrings.commonDone,
          primary: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class SettingsFormDialog extends StatelessWidget {
  const SettingsFormDialog({
    super.key,
    required this.title,
    required this.body,
    this.confirmText,
    this.destructive = false,
    this.enabled = true,
  });

  final String title;
  final Widget body;
  final String? confirmText;
  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TurnaDialogPanel(
      title: title,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [body],
      ),
      actions: [
        TurnaSheetAction(
          label: AppStrings.commonCancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        TurnaSheetAction(
          label: confirmText ?? AppStrings.commonSave,
          primary: true,
          destructive: destructive,
          onPressed: enabled ? () => Navigator.of(context).pop(true) : null,
        ),
      ],
    );
  }
}

class SettingsPrimaryButton extends StatelessWidget {
  const SettingsPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconId,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final TurnaIconId? iconId;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: TurnaTheme.brandTeal,
      foregroundColor: TurnaTheme.textOnPrimary,
      disabledBackgroundColor: TurnaTheme.brandTeal.withValues(alpha: 0.35),
      disabledForegroundColor: TurnaTheme.textOnPrimary.withValues(alpha: 0.7),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg + AppSpacing.xs,
        vertical: AppSpacing.md + 2,
      ),
      shape: TurnaTheme.shape,
      textStyle: AppTextStyles.cardTitle(context),
    );
    if (iconId != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: TurnaIcon(iconId!, size: 18, color: TurnaTheme.textOnPrimary),
        label: Text(label),
        style: style,
      );
    }
    if (icon != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: style,
      );
    }
    return FilledButton(onPressed: onPressed, style: style, child: Text(label));
  }
}

/// Compact form-row used inside [SettingsFormDialog] and inline list
/// editors. Renders a label on the left and a trailing widget (Switch,
/// Dropdown, Slider value, etc.) on the right. Vertical padding matches
/// the main settings list so form-in-dialog feels native.
