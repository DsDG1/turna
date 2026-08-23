// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/views/theme.dart';

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
                              flex: (s.value / total * 1000)
                                  .round()
                                  .clamp(1, 1000),
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
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: TurnaTheme.textSecondaryColor(context),
                              ),
                        ),
                        if (s.formattedValue != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            s.formattedValue!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
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
