import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/views/widgets/glass_surface.dart';
import 'package:turna/views/widgets/turna_icon.dart';

/// 玻璃卡的**预设**：固定 4px 圆角，并把 `tintAlpha` 换算成 [GlassSurface.scale]。
class SoftCard extends StatelessWidget {
  final Color accentColor;
  final Widget child;
  final VoidCallback? onTap;
  final GestureLongPressCallback? onLongPress;
  final double tintAlpha;
  final String? semanticsHint;
  final bool frost;

  const SoftCard({
    required this.accentColor,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.tintAlpha = 0.10,
    this.semanticsHint,
    this.frost = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      accent: accentColor,
      radius: TurnaTheme.borderRadius,
      scale: tintAlpha / 0.10,
      frost: frost,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticsHint: semanticsHint,
      child: child,
    );
  }
}

class AccentIconChip extends StatelessWidget {
  final TurnaIconId icon;
  final Color color;
  final double size;
  final double padding;

  const AccentIconChip({
    required this.icon,
    required this.color,
    this.size = 26,
    this.padding = 10,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        gradient: TurnaTheme.glassFill(context, color, level: GlassLevel.badge),
        borderRadius: TurnaTheme.borderRadius,
      ),
      child: TurnaIcon(icon, color: color, size: size),
    );
  }
}

class CountBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool circular;

  const CountBadge({
    required this.label,
    required this.color,
    this.circular = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: circular
          ? const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2)
          : const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm + 2,
              vertical: AppSpacing.xs,
            ),
      decoration: BoxDecoration(
        color: color,
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : TurnaTheme.borderRadius,
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? TurnaTheme.glassBorder(context)
              : Colors.transparent,
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption(context).copyWith(
          color: TurnaTheme.textOnPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionTitle({required this.title, this.trailing, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: AppTextStyles.sectionTitle(context)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

@Preview(name: 'Cards · light', group: 'Wetland mist')
@Preview(
  name: 'Cards · dark',
  group: 'Wetland mist',
  brightness: Brightness.dark,
)
Widget turnaCardsPreview() => const SoftCard(
  accentColor: TurnaTheme.brandTeal,
  child: Padding(
    padding: EdgeInsets.all(AppSpacing.lg),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AccentIconChip(icon: TurnaIconId.repeat, color: TurnaTheme.brandTeal),
        SizedBox(width: AppSpacing.md),
        CountBadge(label: '12', color: TurnaTheme.anatolianClay),
      ],
    ),
  ),
);
