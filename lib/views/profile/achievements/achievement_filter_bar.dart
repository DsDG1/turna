// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

enum AchievementFilter { all, inProgress, unlocked }

/// Filter chips for the badge grid.
class AchievementFilterBar extends StatelessWidget {
  final AchievementFilter selected;
  final ValueChanged<AchievementFilter> onChanged;
  final int inProgressCount;
  final int unlockedCount;

  const AchievementFilterBar({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.inProgressCount,
    required this.unlockedCount,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _chip(context, AchievementFilter.all, AppStrings.achievementsFilterAll,
              null),
          const SizedBox(width: 8),
          _chip(context, AchievementFilter.inProgress,
              AppStrings.achievementsFilterInProgress, inProgressCount),
          const SizedBox(width: 8),
          _chip(context, AchievementFilter.unlocked,
              AppStrings.achievementsFilterUnlocked, unlockedCount),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    AchievementFilter filter,
    String label,
    int? count,
  ) {
    final isSelected = filter == selected;
    final accent = TurnaTheme.anatolianClay;
    final text = count == null ? label : '$label $count';
    return Semantics(
      button: true,
      selected: isSelected,
      label: text,
      child: Material(
        color: isSelected
            ? accent.withValues(alpha: 0.14)
            : TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
        child: InkWell(
          onTap: () => onChanged(filter),
          borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
              border: Border.all(
                color:
                    isSelected ? accent : TurnaTheme.statCardBorder(context),
              ),
            ),
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: isSelected ? accent : TurnaTheme.textSecondaryColor(context),
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
