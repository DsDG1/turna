// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/core/extensions.dart';
import 'package:varnamala/views/theme.dart';

class Statistics extends StatelessWidget {
  const Statistics({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, 'Statistics', Icons.bar_chart_rounded),
          // The StreamBuilders already react to state changes; wrapping them in
          // Consumers would just re-subscribe on every notifyListeners (XP
          // award, streak check, lesson completion) for no benefit.
          StreamBuilder(
            stream: context.read<GameProvider>().getUserGameStateStream(),
            builder: (context, snapshot) {
              final data = snapshot.data;
              final streak = data?.streak ?? 0;
              final totalXp = data?.score ?? 0;
              const currentLanguage = 'Turkish';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  _LanguageChip(language: currentLanguage.toTitleCase),
                  const SizedBox(height: 12),
                  GridView.count(
                    primary: false,
                    shrinkWrap: true,
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 2.2,
                    children: [
                      _StatCard(
                        icon: Icons.local_fire_department_rounded,
                        iconColor: VarnamalaTheme.warning,
                        value: streak.toString(),
                        label: 'Day Streak',
                      ),
                      _StatCard(
                        icon: Icons.bolt_rounded,
                        iconColor: VarnamalaTheme.peacockTurquoise,
                        value: totalXp.toString(),
                        label: 'Total XP',
                      ),
                      StreamBuilder<int>(
                        stream: context.read<GemsProvider>().getGemsStream(),
                        builder: (context, snap) {
                          final gems = snap.data ?? 0;
                          return _StatCard(
                            icon: Icons.diamond_rounded,
                            iconColor: VarnamalaTheme.error,
                            value: gems.toString(),
                            label: 'Gems',
                          );
                        },
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: VarnamalaTheme.peacockTeal, size: 22),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  final String language;
  const _LanguageChip({required this.language});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(VarnamalaTheme.radiusRound),
          ),
          child: Text(
            language,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.peacockTeal,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: VarnamalaTheme.textHintColor(context),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}