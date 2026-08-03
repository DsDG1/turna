// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/views/theme.dart';

/// Shared visual building blocks for the AI tutor surfaces (config page, hint
/// sheet, depth-tutor sheet, chat page) so they share one card-based design
/// language: soft-tint group cards with a glass hairline border, tinted input
/// fields, and a matching primary/secondary button pair.
///
/// Extracted from the config form's former private `_groupCard` /
/// `_fieldDecoration` so every AI surface reuses the exact same look without
/// duplicating the theme-token wiring.

/// A group card: soft-tint fill, 1px glass border, rounded corners, with an
/// accent icon + title header. The canonical "card element" used across the AI
/// sheets.
class AiGroupCard extends StatelessWidget {
  const AiGroupCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.all(14),
    this.accent,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  /// Accent color for the header icon. Defaults to the peacock teal accent.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final a = VarnamalaTheme.accentOnCard(
        context, accent ?? VarnamalaTheme.peacockTeal);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: VarnamalaTheme.softTint(
            context, accent ?? VarnamalaTheme.peacockTeal),
        borderRadius:
            BorderRadius.circular(VarnamalaTheme.radiusXLarge - 4),
        border: Border.all(
          color: VarnamalaTheme.glassBorder(context),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: a),
              const SizedBox(width: 6),
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: VarnamalaTheme.textPrimaryColor(context),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// A headerless card surface with the same soft-tint + glass-border treatment
/// as [AiGroupCard], for content blocks that don't need a titled header (e.g.
/// an explanation body or a result panel).
class AiSurfaceCard extends StatelessWidget {
  const AiSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: VarnamalaTheme.softTint(
            context, accent ?? VarnamalaTheme.peacockTeal),
        borderRadius:
            BorderRadius.circular(VarnamalaTheme.radiusXLarge - 4),
        border: Border.all(
          color: VarnamalaTheme.glassBorder(context),
          width: 1,
        ),
      ),
      child: child,
    );
  }
}

/// Unified input decoration for AI sheets: tint fill, radiusMedium, no hard
/// border, teal hairline on focus. Pass [label] for a floating label or
/// [hint] for placeholder text.
InputDecoration aiSheetInputDecoration(
  BuildContext context, {
  String? hint,
  String? label,
  Widget? suffixIcon,
}) {
  final base = OutlineInputBorder(
    borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
    borderSide: BorderSide.none,
  );
  return InputDecoration(
    hintText: hint,
    labelText: label,
    hintStyle: TextStyle(color: VarnamalaTheme.textHintColor(context)),
    filled: true,
    fillColor: VarnamalaTheme.tintLight,
    isDense: true,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    suffixIcon: suffixIcon,
    border: base,
    enabledBorder: base,
    disabledBorder: base,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      borderSide: const BorderSide(
        color: VarnamalaTheme.peacockTeal,
        width: 1.2,
      ),
    ),
  );
}

/// Primary (filled) button style for AI sheets: radiusLarge, bold label.
ButtonStyle aiSheetPrimaryButtonStyle() => FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
      ),
      textStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );

/// Secondary (outlined) button style for AI sheets: radiusMedium, teal border.
ButtonStyle aiSheetSecondaryButtonStyle() => OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      ),
      side: BorderSide(
        color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.5),
      ),
    );
