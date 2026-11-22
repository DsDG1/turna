// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/theme.dart';

/// Shared visual building blocks for the AI tutor surfaces (config page, hint
/// sheet, depth-tutor sheet, chat page) using the unified 4px flat paper
/// surface and input/button language.

/// A headerless flat-paper card surface (4px radius + 1px hairline border),
/// for content blocks that don't need a titled header (e.g. an explanation body
/// or a result panel).
class AiSurfaceCard extends StatelessWidget {
  const AiSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final base = TurnaTheme.flatPaperDecoration(context);
    return Container(
      padding: padding,
      decoration: accent == null
          ? base
          : base.copyWith(color: TurnaTheme.softTint(context, accent!)),
      child: child,
    );
  }
}

/// Unified input decoration for AI sheets: tint fill, 4px border radius,
/// neutral hairline, teal hairline on focus. Pass [label] for a floating label
/// or [hint] for placeholder text.
InputDecoration aiSheetInputDecoration(
  BuildContext context, {
  String? hint,
  String? label,
  Widget? suffixIcon,
}) {
  final base = OutlineInputBorder(
    borderRadius: TurnaTheme.borderRadius,
    borderSide: BorderSide(color: TurnaTheme.dividerBg(context)),
  );
  return InputDecoration(
    hintText: hint,
    labelText: label,
    hintStyle: TextStyle(color: TurnaTheme.textHintColor(context)),
    filled: true,
    fillColor: TurnaTheme.tintLight,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md + 2,
      vertical: AppSpacing.md,
    ),
    suffixIcon: suffixIcon,
    border: base,
    enabledBorder: base,
    disabledBorder: base,
    focusedBorder: const OutlineInputBorder(
      borderRadius: TurnaTheme.borderRadius,
      borderSide: BorderSide(color: TurnaTheme.brandTeal, width: 1.2),
    ),
  );
}

/// Primary (filled) button style for AI sheets: 4px geometric shape.
ButtonStyle aiSheetPrimaryButtonStyle() => FilledButton.styleFrom(
  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
  shape: TurnaTheme.shape,
);

/// Secondary (outlined) button style for AI sheets: 4px shape, teal border.
ButtonStyle aiSheetSecondaryButtonStyle() => OutlinedButton.styleFrom(
  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 1),
  shape: TurnaTheme.shape,
  side: BorderSide(color: TurnaTheme.brandTeal.withValues(alpha: 0.5)),
);
