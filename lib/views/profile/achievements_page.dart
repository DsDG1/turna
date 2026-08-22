// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/fun_provider.dart';
import 'package:turna/domain/achievements/achievement_catalog.dart';
import 'package:turna/domain/achievements/achievement_state.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/achievements/achievement_badge_card.dart';
import 'package:turna/views/profile/achievements/achievement_detail_sheet.dart';
import 'package:turna/views/profile/achievements/achievement_filter_bar.dart';
import 'package:turna/views/profile/achievements/achievement_overview_header.dart';
import 'package:turna/views/profile/achievements/achievement_ui_catalog.dart';
import 'package:turna/views/theme.dart';

/// Badge-collection achievements home (plan §7.2): overview hero, nearest
/// recommendations, filter chips, a two-column badge grid, and the recent
/// unlocks strip. Everything reads the persisted v2 state through
/// [AchievementService]; nothing derives unlock state locally.
@RoutePage()
class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  AchievementFilter _filter = AchievementFilter.all;
  List<String>? _unseenOnEnter;
  late final AchievementService _service;

  @override
  void initState() {
    super.initState();
    _service = context.read<AchievementService>();
    // Capture the unseen set on entry, then ensure state is loaded; NEW
    // markers render from the captured set during this visit and are cleared
    // when the page closes (dispose).
    _unseenOnEnter = _service.unseenLiveUnlocks.map((t) => t.tierId).toList();
    _service.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    // Leaving the page counts as having seen the badges shown during the
    // visit (NEW markers don't persist across the next visit).
    final unseen = _unseenOnEnter;
    if (unseen != null && unseen.isNotEmpty) {
      _service.markSeen(unseen.toSet());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AchievementService>();
    final showAllUnlocked =
        context.select<FunProvider, bool>((p) => p.allAchievementsUnlocked);

    final views = service.progressViews();
    final totalCount = AchievementCatalog.totalBadgeCount;
    final unlockedCount = showAllUnlocked
        ? totalCount
        : service.unlockedBadgeCount;
    final latest = service.latestUnlock;

    final inProgressViews = views
        .where((v) =>
            !v.isSeriesComplete && v.currentProgress > 0)
        .toList(growable: false);
    final unlockedViews =
        views.where((v) => v.completedTierCount > 0).toList(growable: false);

    final filtered = switch (_filter) {
      AchievementFilter.all => views,
      AchievementFilter.inProgress => inProgressViews,
      AchievementFilter.unlocked => unlockedViews,
    };

    final nearest = _nearestRecommendations(views);

    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(AppStrings.profileAchievementsTitle),
        backgroundColor: TurnaTheme.scaffoldBg(context),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(
          top: 8,
          bottom: 24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AchievementOverviewHeader(
                unlockedCount: unlockedCount,
                totalCount: totalCount,
                latestUnlockAt: latest?.unlockedAt,
              ),
            ),
            if (showAllUnlocked)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  AppStrings.achievementsFunPreviewBanner,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: TurnaTheme.textHintColor(context),
                      ),
                ),
              ),
            if (nearest.isNotEmpty) ...[
              _SectionTitle(title: AppStrings.achievementsNearestSection),
              ...nearest.map(
                (seriesId) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _NearestTile(seriesId: seriesId, views: views),
                ),
              ),
            ],
            _SectionTitle(
              title: AppStrings.achievementsFilterAll,
              topPadding: 12,
            ),
            AchievementFilterBar(
              selected: _filter,
              onChanged: (f) => setState(() => _filter = f),
              inProgressCount: inProgressViews.length,
              unlockedCount: unlockedViews.length,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.98,
                children: [
                  for (final view in filtered)
                    _GridCard(
                      view: view,
                      funPreview: showAllUnlocked,
                      onTap: () => _openDetail(context, service, view.seriesId),
                    ),
                ],
              ),
            ),
            if (_filter == AchievementFilter.all) ...[
              _SectionTitle(
                title: AppStrings.achievementsRecentSection,
                topPadding: 20,
              ),
              _RecentStrip(service: service),
            ],
          ],
        ),
      ),
    );
  }

  /// 1–2 series closest to their next tier by ratio; zero-progress series
  /// never take a recommendation slot (plan §7.2).
  List<String> _nearestRecommendations(List<AchievementSeriesProgress> views) {
    final candidates = <_NearestCandidate>[];
    for (final view in views) {
      final next = view.nextTier;
      if (next == null || view.currentProgress <= 0) continue;
      candidates.add(_NearestCandidate(
        seriesId: view.seriesId,
        ratio: (view.currentProgress / next.target).clamp(0.0, 1.0),
      ));
    }
    candidates.sort((a, b) => b.ratio.compareTo(a.ratio));
    return candidates.take(2).map((c) => c.seriesId).toList(growable: false);
  }

  void _openDetail(
    BuildContext context,
    AchievementService service,
    String seriesId,
  ) {
    final series = AchievementCatalog.seriesById(seriesId);
    if (series == null) return;
    showAchievementDetailSheet(
      context: context,
      series: series,
      progress: service.progressFor(seriesId),
      service: service,
    );
  }
}

class _NearestCandidate {
  final String seriesId;
  final double ratio;
  const _NearestCandidate({required this.seriesId, required this.ratio});
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final double topPadding;

  const _SectionTitle({required this.title, this.topPadding = 20});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _NearestTile extends StatelessWidget {
  final String seriesId;
  final List<AchievementSeriesProgress> views;

  const _NearestTile({required this.seriesId, required this.views});

  @override
  Widget build(BuildContext context) {
    final view = views.firstWhere((v) => v.seriesId == seriesId);
    final service = context.read<AchievementService>();
    return AchievementNearestCard(
      seriesId: seriesId,
      progress: view,
      nextTarget: view.nextTier?.target ?? view.currentProgress,
      onTap: () {
        final series = AchievementCatalog.seriesById(seriesId);
        if (series == null) return;
        showAchievementDetailSheet(
          context: context,
          series: series,
          progress: service.progressFor(seriesId),
          service: service,
        );
      },
    );
  }
}

class _GridCard extends StatelessWidget {
  final AchievementSeriesProgress view;
  final bool funPreview;
  final VoidCallback onTap;

  const _GridCard({
    required this.view,
    required this.funPreview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final series = AchievementCatalog.seriesById(view.seriesId);
    if (series == null) return const SizedBox.shrink();
    return AchievementBadgeCard(
      series: series,
      progress: view,
      funPreview: funPreview,
      onTap: onTap,
    );
  }
}

/// Recent unlocks strip: `unlockedAt` descending, live before migration.
class _RecentStrip extends StatelessWidget {
  final AchievementService service;

  const _RecentStrip({required this.service});

  @override
  Widget build(BuildContext context) {
    final entries = service.state.unlockedTiers.values
        .where((t) => AchievementCatalog.tierById(t.tierId) != null)
        .toList()
      ..sort((a, b) {
        // Live unlocks first (by time desc), migration backfills after.
        if (a.origin != b.origin) {
          return a.origin == AchievementUnlockOrigin.live ? -1 : 1;
        }
        return b.unlockedAt.compareTo(a.unlockedAt);
      });

    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          AppStrings.achievementsRecentEmpty,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TurnaTheme.textHintColor(context),
              ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final entry in entries.take(5))
            _RecentRow(
              tierId: entry.tierId,
              origin: entry.origin,
              unlockedAt: entry.unlockedAt,
            ),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final String tierId;
  final AchievementUnlockOrigin origin;
  final DateTime unlockedAt;

  const _RecentRow({
    required this.tierId,
    required this.origin,
    required this.unlockedAt,
  });

  @override
  Widget build(BuildContext context) {
    final tier = AchievementCatalog.tierById(tierId);
    if (tier == null) return const SizedBox.shrink();
    final series = AchievementCatalog.allSeries
        .where((s) => s.tiers.contains(tier))
        .first;
    final accent = AchievementUiCatalog.colorFor(series.id);
    final date =
        '${unlockedAt.year}-${unlockedAt.month.toString().padLeft(2, '0')}-${unlockedAt.day.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
      child: Row(
        children: [
          Icon(AchievementUiCatalog.iconFor(series.id),
              color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${AchievementUiCatalog.titleFor(series.id)} · '
              '${tier.rarity.displayName} ${tier.target} '
              '${AchievementUiCatalog.unitFor(series.metric)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (origin == AchievementUnlockOrigin.migration)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                AppStrings.achievementsMigrationBackfillTag,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: TurnaTheme.textHintColor(context),
                    ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                date,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: TurnaTheme.textHintColor(context),
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
