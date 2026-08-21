// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/achievements_provider.dart';
import 'package:turna/application/fun_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/domain/game/user_game_state.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/home/components/profile_app_bar.dart';
import 'package:turna/views/profile/widgets/learning_stats.dart';
import 'package:turna/views/profile/widgets/widgets.dart';
import 'package:turna/views/theme.dart';

/// Slim profile page: identity hero, today's one-glance summary, review
/// quick entries, and links to the stats / achievements detail pages. All
/// duplicated counters (streak/XP/gems live in the Learn app bar) and the
/// detailed stats/achievement lists moved to their own pages.
class ProfilePage extends StatelessWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: AccountWidget(
              onShare: () => ProfileAppBar.openShareSheet(context),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        const SliverToBoxAdapter(child: TodaySummaryCard()),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        const SliverToBoxAdapter(child: ProfileQuickActions()),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        const SliverToBoxAdapter(child: _DetailPageEntries()),
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ],
    );
  }
}

/// Entry rows to the stats and achievements detail pages.
class _DetailPageEntries extends StatelessWidget {
  const _DetailPageEntries();

  @override
  Widget build(BuildContext context) {
    final showAllUnlocked = context.select<FunProvider, bool>(
      (provider) => provider.allAchievementsUnlocked,
    );

    return StreamBuilder<UserGameState>(
      stream: context.read<GameProvider>().getUserGameStateStream(),
      builder: (context, snapshot) {
        final total = AchievementsProvider.allAchievements.length;
        final unlocked = showAllUnlocked
            ? total
            : unlockedAchievementCount(
                snapshot.data ?? UserGameState.empty,
              );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: TurnaTheme.cardBg(context),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
              border: Border.all(color: TurnaTheme.statCardBorder(context)),
            ),
            child: Column(
              children: [
                _EntryTile(
                  icon: Icons.insights_rounded,
                  iconColor: TurnaTheme.brandTeal,
                  title: AppStrings.profileLearningStatsTitle,
                  subtitle: AppStrings.profileStatsEntrySubtitle,
                  onTap: () =>
                      context.router.push(const ReviewProgressRoute()),
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: TurnaTheme.dividerBg(context),
                ),
                _EntryTile(
                  icon: Icons.military_tech_rounded,
                  // Achievement section uses secondary brand clay (ADR 0033).
                  iconColor: TurnaTheme.anatolianClay,
                  title: AppStrings.profileAchievementsTitle,
                  subtitle:
                      AppStrings.profileAchievementsUnlocked(unlocked, total),
                  onTap: () =>
                      context.router.push(const AchievementsRoute()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EntryTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _EntryTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textHintColor(context),
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: TurnaTheme.textHintColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
