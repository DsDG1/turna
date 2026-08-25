// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/fun_provider.dart';
import 'package:turna/domain/achievements/achievement_catalog.dart';
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
  const ProfilePage({super.key});

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
    final achievements = context.watch<AchievementService>();
    final total = AchievementCatalog.totalBadgeCount;
    final unlocked = showAllUnlocked ? total : achievements.unlockedBadgeCount;
    final nearComplete = showAllUnlocked
        ? 0
        : achievements
            .progressViews()
            .where((v) =>
                !v.isSeriesComplete &&
                v.nextTier != null &&
                v.currentProgress > 0)
            .length;
    final hasUnseen = !showAllUnlocked && achievements.hasUnseenUnlocks;

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
              onTap: () => context.router.push(const ReviewProgressRoute()),
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
              subtitle: nearComplete > 0
                  ? '${AppStrings.profileAchievementsBadgeCount(unlocked, total)} · '
                      '${AppStrings.profileAchievementsNearComplete(nearComplete)}'
                  : AppStrings.profileAchievementsBadgeCount(unlocked, total),
              showUnseenDot: hasUnseen,
              onTap: () => context.router.push(const AchievementsRoute()),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Warm clay dot marking unseen achievement unlocks.
  final bool showUnseenDot;

  const _EntryTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showUnseenDot = false,
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (showUnseenDot) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: TurnaTheme.anatolianClay,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textHintColor(context),
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
