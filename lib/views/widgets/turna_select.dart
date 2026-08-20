// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/views/theme.dart';

/// Exclusive 2–4 option control. Fill is the selection — no checkmark.
class TurnaSegmented<T> extends StatelessWidget {
  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool expanded;

  const TurnaSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final button = SegmentedButton<T>(
      segments: segments,
      selected: {selected},
      showSelectedIcon: false,
      emptySelectionAllowed: false,
      onSelectionChanged: (set) {
        if (set.isEmpty) return;
        onChanged(set.first);
      },
    );
    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

/// Icon + label choice card for longer exclusive options (2–4 items).
class TurnaChoiceCard<T> extends StatelessWidget {
  final T value;
  final T selected;
  final String label;
  final IconData? icon;
  final ValueChanged<T> onSelected;

  const TurnaChoiceCard({
    super.key,
    required this.value,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final on = value == selected;
    const accent = TurnaTheme.brandTeal;
    final radius = BorderRadius.circular(TurnaTheme.radiusLarge);
    return Material(
      color: on
          ? accent.withValues(alpha: 0.14)
          : TurnaTheme.cardBg(context),
      borderRadius: radius,
      child: InkWell(
        onTap: () => onSelected(value),
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: on ? accent : TurnaTheme.statCardBorder(context),
              width: on ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 20,
                  color: on ? accent : TurnaTheme.textHintColor(context),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on
                        ? accent
                        : TurnaTheme.textPrimaryColor(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2-column grid of [TurnaChoiceCard]s.
class TurnaChoiceGrid<T> extends StatelessWidget {
  final List<(T value, String label, IconData? icon)> items;
  final T selected;
  final ValueChanged<T> onSelected;

  const TurnaChoiceGrid({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (items.length <= 2) {
      return Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            TurnaChoiceCard<T>(
              value: items[i].$1,
              selected: selected,
              label: items[i].$2,
              icon: items[i].$3,
              onSelected: onSelected,
            ),
          ],
        ],
      );
    }
    return GridView.count(
      padding: EdgeInsets.zero,
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.5,
      children: [
        for (final item in items)
          TurnaChoiceCard<T>(
            value: item.$1,
            selected: selected,
            label: item.$2,
            icon: item.$3,
            onSelected: onSelected,
          ),
      ],
    );
  }
}

/// Filter / toggle chip without the old checkmark. Selected fill is enough.
class TurnaFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final Widget? avatar;

  const TurnaFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.avatar,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      avatar: avatar,
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: onSelected,
    );
  }
}
