import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/glass_surface.dart';

class SoftCard extends StatelessWidget {
  final Color accentColor;
  final Widget child;
  final VoidCallback? onTap;
  final GestureLongPressCallback? onLongPress;
  final double tintAlpha;

  const SoftCard({
    required this.accentColor,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.tintAlpha = 0.10,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      accent: accentColor,
      radius: const BorderRadius.all(Radius.circular(TurnaTheme.cardRadius)),
      scale: tintAlpha / 0.10,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticsHint: onLongPress == null ? null : AppStrings.playLongPressHint,
      child: child,
    );
  }
}

class AccentIconChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double padding;
  final double radius;

  const AccentIconChip({
    required this.icon,
    required this.color,
    this.size = 26,
    this.padding = 10,
    this.radius = 12,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        gradient: TurnaTheme.glassFill(
          context,
          color,
          level: GlassLevel.badge,
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, color: color, size: size),
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
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.transparent,
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: TurnaTheme.textOnPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

@Preview(name: 'Cards · light', group: 'Wetland mist')
@Preview(
    name: 'Cards · dark', group: 'Wetland mist', brightness: Brightness.dark)
Widget turnaCardsPreview() => SoftCard(
      accentColor: TurnaTheme.brandTeal,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AccentIconChip(
                icon: Icons.repeat_rounded, color: TurnaTheme.brandTeal),
            SizedBox(width: 12),
            Text('Tekrar ve hatırlama'),
          ],
        ),
      ),
    );
