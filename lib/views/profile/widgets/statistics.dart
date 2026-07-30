// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/theme.dart';

/// Compact 4-metric strip: streak, total XP, gems, lessons completed.
class Statistics extends StatelessWidget {
  const Statistics({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, AppStrings.profileKeyMetricsTitle),
          const SizedBox(height: 10),
          StreamBuilder(
            stream: context.read<GameProvider>().getUserGameStateStream(),
            builder: (context, snapshot) {
              final data = snapshot.data;
              final streak = data?.streak ?? 0;
              final totalXp = data?.score ?? 0;
              final lessons = data?.lessonsCompleted ?? 0;
              return StreamBuilder<int>(
                stream: context.read<GemsProvider>().getGemsStream(),
                builder: (context, gemsSnap) {
                  final gems = gemsSnap.data ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 14),
                    decoration: BoxDecoration(
                      color: VarnamalaTheme.cardBg(context),
                      borderRadius:
                          BorderRadius.circular(VarnamalaTheme.radiusLarge),
                      border: Border.all(
                          color: VarnamalaTheme.statCardBorder(context)),
                    ),
                    child: Row(
                      children: [
                        _MetricCell(
                          icon: Icons.local_fire_department_rounded,
                          iconColor: VarnamalaTheme.warning,
                          value: streak.toString(),
                          label: AppStrings.profileDayStreak,
                        ),
                        _vDivider(context),
                        _MetricCell(
                          icon: Icons.bolt_rounded,
                          iconColor: VarnamalaTheme.peacockTurquoise,
                          value: totalXp.toString(),
                          label: AppStrings.profileTotalXp,
                        ),
                        _vDivider(context),
                        _MetricCell(
                          icon: Icons.diamond_rounded,
                          iconColor: VarnamalaTheme.error,
                          value: gems.toString(),
                          label: AppStrings.profileGems,
                        ),
                        _vDivider(context),
                        _MetricCell(
                          icon: Icons.school_rounded,
                          iconColor: VarnamalaTheme.peacockCyan,
                          value: lessons.toString(),
                          label: AppStrings.profileLessonsShort,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Row(
      children: [
        const Icon(Icons.insights_rounded,
            color: VarnamalaTheme.peacockTeal, size: 20),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }

  Widget _vDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: VarnamalaTheme.dividerBg(context),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _MetricCell({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: VarnamalaTheme.textHintColor(context),
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                ),
          ),
        ],
      ),
    );
  }
}
