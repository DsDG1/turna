// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki_official/engine/official_anki_home_due_sync.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/widgets/glass_surface.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_top_bar.dart';

/// Anki review hub — lists imported Anki sections with due counts,
/// allows starting a review session for a selected section.
@RoutePage()
class AnkiReviewPage extends StatelessWidget {
  const AnkiReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: TurnaTopBar(
        title: AppStrings.ankiReviewScreenTitle,
        onBack: () => context.router.maybePop(),
        actions: [
          IconButton(
            icon: const TurnaIcon(
              TurnaIconId.upload,
              size: 20,
              color: TurnaTheme.brandTeal,
            ),
            tooltip: AppStrings.ankiImportNewDeck,
            onPressed: () => context.router.push(AnkiImportRoute()),
          ),
        ],
      ),
      body: const _AnkiReviewBody(),
    );
  }
}

class _AnkiReviewBody extends StatefulWidget {
  const _AnkiReviewBody();

  @override
  State<_AnkiReviewBody> createState() => _AnkiReviewBodyState();
}

class _AnkiReviewBodyState extends State<_AnkiReviewBody> {
  @override
  void initState() {
    super.initState();
    unawaited(_refreshOfficialDue());
  }

  Future<void> _refreshOfficialDue() async {
    await const OfficialAnkiHomeDueSync().refresh();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final courseProvider = context.watch<CourseProvider>();

    // Find Anki sections (allSections: the review hub lists decks even when
    // the course scope hides them from the Learn-page tree).
    final ankiSections = courseProvider.allSections
        .where((s) => s.level == 'Anki' || s.level == 'OfficialAnki')
        .toList();

    // Deck tiles sort by the persisted course order (wire keys); the
    // per-section wire resolves through the catalog import ids.
    final wireForImportId = <String, String>{};
    for (final entry in courseProvider.catalogEntries) {
      final id = entry.officialSourceId;
      if (id != null) wireForImportId[id] = entry.wireKey;
    }
    final deckOrder = {
      for (var i = 0; i < courseProvider.catalogEntries.length; i++)
        courseProvider.catalogEntries[i].wireKey: i,
    };
    ankiSections.sort(
      (a, b) =>
          (deckOrder[wireForImportId[LegacyAnkiIdentifiers.importIdFromSectionId(
                    a.id,
                  )]] ??
                  9999)
              .compareTo(
                deckOrder[wireForImportId[LegacyAnkiIdentifiers.importIdFromSectionId(
                      b.id,
                    )]] ??
                    9999,
              ),
    );

    if (ankiSections.isEmpty) {
      return _buildEmptyState(context);
    }

    // Doc 35 L2: the Legacy assembler is gone — due badges aggregate the
    // official due repository only. Legacy sections read 0 (fail-closed).
    final totalDue = _aggregatedDue(ankiSections);
    final unintroducedNew =
        OfficialFormalDueRepository.instance.snapshot.unintroducedOfficialDue;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            AppSpacing.sm,
            AppSpacing.pageMargin,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: OfficialFormalDueRepository.instance.snapshot.unavailable
                ? _AnkiDueUnavailableBanner(onRetry: _refreshOfficialDue)
                : _AnkiDueHero(
                    introducedDue: totalDue,
                    unintroducedNew: unintroducedNew,
                    onReviewAll: totalDue > 0
                        ? () => _startReview(
                            context,
                            null,
                            entry: FormalReviewEntryKind.courseReview,
                          )
                        : null,
                  ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            AppSpacing.xl,
            AppSpacing.pageMargin,
            AppSpacing.md,
          ),
          sliver: SliverToBoxAdapter(
            child: Text(
              AppStrings.ankiHubDecksTitle,
              style: AppTextStyles.sectionTitle(context),
            ),
          ),
        ),
        // Section list. The order is persisted in the same course-order
        // preference used by the course-management screen.
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            0,
            AppSpacing.pageMargin,
            AppSpacing.xl,
          ),
          sliver: SliverToBoxAdapter(
            child: ReorderableListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: ankiSections.length,
              onReorderItem: (oldIndex, newIndex) =>
                  _reorderDecks(context, ankiSections, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final section = ankiSections[index];
                final importId = LegacyAnkiIdentifiers.importIdFromSectionId(
                  section.id,
                );
                return KeyedSubtree(
                  key: ValueKey(section.id),
                  child: _AnkiSectionCard(
                    index: index,
                    sectionId: section.id,
                    sectionName: section.name,
                    description: section.description,
                    dueCount: _dueForSection(importId),
                    onTap: () => _startReview(
                      context,
                      section.id,
                      entry: FormalReviewEntryKind.deckSection,
                    ),
                    onStats: () => context.router.push(
                      AnkiDeckStatsRoute(
                        importId: importId,
                        title: section.name,
                      ),
                    ),
                    onBrowse: () => context.router.push(
                      AnkiCardBrowserRoute(
                        importId: importId,
                        title: section.name,
                        sectionId: section.id,
                      ),
                    ),
                    onPin: () => _pinDeck(context, section.id),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _reorderDecks(
    BuildContext context,
    List<Section> sections,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = List<Section>.of(sections);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    await context.read<CourseProvider>().reorderAnkiDecks([
      for (final section in reordered)
        LegacyAnkiIdentifiers.importIdFromSectionId(section.id),
    ]);
  }

  Future<void> _pinDeck(BuildContext context, String sectionId) {
    final importId = LegacyAnkiIdentifiers.importIdFromSectionId(sectionId);
    return context.read<CourseProvider>().pinAnkiDeck(importId);
  }

  Widget _buildEmptyState(BuildContext context) {
    return PracticeEmptyState(
      title: AppStrings.ankiNoDecksTitle,
      message: AppStrings.ankiNoDecksSubtitle,
      actionLabel: AppStrings.ankiImportDeck,
      onAction: () => context.router.push(AnkiImportRoute()),
    );
  }

  int? _dueForSection(String importId) {
    if (OfficialFormalDueRepository.instance.officialImportIds.contains(
      importId,
    )) {
      if (OfficialFormalDueRepository.instance.snapshot.unavailable) {
        return null;
      }
      return OfficialFormalDueRepository.instance.formalOfficialDueForImport(
        importId,
      );
    }
    // Legacy-owned section: scheduler retired (doc 35 L2), nothing is due.
    return 0;
  }

  int _aggregatedDue(List<Section> ankiSections) {
    var total = 0;
    for (final section in ankiSections) {
      total +=
          _dueForSection(
            LegacyAnkiIdentifiers.importIdFromSectionId(section.id),
          ) ??
          0;
    }
    return total;
  }

  void _startReview(
    BuildContext context,
    String? sectionId, {
    FormalReviewEntryKind entry = FormalReviewEntryKind.ankiHub,
  }) {
    unawaited(_startReviewAsync(context, sectionId, entry: entry));
  }

  Future<void> _startReviewAsync(
    BuildContext context,
    String? sectionId, {
    FormalReviewEntryKind entry = FormalReviewEntryKind.ankiHub,
  }) async {
    final importId = sectionId == null
        ? ''
        : LegacyAnkiIdentifiers.importIdFromSectionId(sectionId);
    await const FormalReviewLauncher().open(
      context,
      entry: entry,
      courseId: importId.isEmpty ? 'anki' : 'anki-$importId',
      sectionId: sectionId,
      officialOwner: OfficialFormalDueRepository.instance.officialImportIds
          .contains(importId),
      schedulerRuntimeAvailable:
          OfficialAnkiFeatureFlags.current.allowsOfficialScheduler,
    );
  }
}

class _AnkiDueUnavailableBanner extends StatelessWidget {
  const _AnkiDueUnavailableBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('anki-due-unavailable'),
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.sm, 14),
      decoration: BoxDecoration(
        color: TurnaTheme.warning.withValues(alpha: 0.08),
        borderRadius: TurnaTheme.borderRadius,
        border: Border.all(color: TurnaTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: TurnaTheme.warning.withValues(alpha: 0.14),
              borderRadius: TurnaTheme.borderRadius,
            ),
            child: const TurnaIcon(
              TurnaIconId.warning,
              color: TurnaTheme.warning,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              AppStrings.ankiDueUnavailable,
              style: AppTextStyles.cardTitle(context),
            ),
          ),
          IconButton(
            tooltip: AppStrings.ankiReviewRetry,
            onPressed: onRetry,
            icon: TurnaIcon(
              TurnaIconId.refresh,
              size: 20,
              color: TurnaTheme.textPrimaryColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hub hero: due CTA when anything is owed, otherwise a calm caught-up card.
class _AnkiDueHero extends StatelessWidget {
  const _AnkiDueHero({
    required this.introducedDue,
    required this.unintroducedNew,
    this.onReviewAll,
  });

  final int introducedDue;
  final int unintroducedNew;
  final VoidCallback? onReviewAll;

  @override
  Widget build(BuildContext context) {
    if (introducedDue <= 0 && unintroducedNew <= 0) {
      return const _AnkiCaughtUpCard();
    }

    return Semantics(
      button: onReviewAll != null,
      label: AppStrings.ankiReviewAll,
      child: GlassSurface(
        key: const Key('anki-review-hub-hero'),
        accent: TurnaTheme.brandTeal,
        frost: true,
        radius: TurnaTheme.borderRadius,
        onTap: onReviewAll,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AnkiDueHeroHeader(
              introducedDue: introducedDue,
              unintroducedNew: unintroducedNew,
            ),
            if (onReviewAll != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _AnkiReviewAllButton(onPressed: onReviewAll!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Caught-up hero shown when nothing is introduced-due or new.
class _AnkiCaughtUpCard extends StatelessWidget {
  const _AnkiCaughtUpCard();

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      key: const Key('anki-review-hub-caught-up'),
      accent: TurnaTheme.brandTeal,
      level: GlassLevel.l1Subtle,
      radius: TurnaTheme.borderRadius,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: TurnaTheme.softTint(
                context,
                TurnaTheme.brandTeal,
                alpha: 0.12,
              ),
              borderRadius: TurnaTheme.borderRadius,
            ),
            child: const TurnaIcon(
              TurnaIconId.checkCircle,
              size: 20,
              color: TurnaTheme.brandTeal,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.ankiHubCaughtUpTitle,
                  style: AppTextStyles.cardTitle(context),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppStrings.ankiHubCaughtUpMessage,
                  style: AppTextStyles.captionSm(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Header row of the due hero: deck icon, screen title + due breakdown,
/// and the big introduced-due counter on the right.
class _AnkiDueHeroHeader extends StatelessWidget {
  const _AnkiDueHeroHeader({
    required this.introducedDue,
    required this.unintroducedNew,
  });

  final int introducedDue;
  final int unintroducedNew;

  @override
  Widget build(BuildContext context) {
    final accent = TurnaTheme.accentOnCard(context, TurnaTheme.brandTeal);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: TurnaTheme.softTint(
              context,
              TurnaTheme.brandTeal,
              alpha: 0.14,
            ),
            borderRadius: TurnaTheme.borderRadius,
            border: Border.all(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.25),
            ),
          ),
          child: TurnaIcon(TurnaIconId.cards, color: accent, size: 22),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.ankiReviewScreenTitle,
                style: AppTextStyles.sectionTitle(context),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppStrings.ankiFormalDueBreakdown(
                  introducedDue: introducedDue,
                  unintroducedNew: unintroducedNew,
                ),
                style: AppTextStyles.captionSm(context),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$introducedDue',
              style: AppTextStyles.metricHero(
                context,
                color: accent,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            Text(
              AppStrings.ankiHubDueCountLabel,
              style: AppTextStyles.caption(context).copyWith(letterSpacing: 0),
            ),
          ],
        ),
      ],
    );
  }
}

/// Full-width "复习全部" CTA under the due-hero header.
class _AnkiReviewAllButton extends StatelessWidget {
  const _AnkiReviewAllButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: TurnaTheme.brandTeal,
          foregroundColor: TurnaTheme.textOnPrimary,
          shape: TurnaTheme.shape,
        ),
        icon: const TurnaIcon(
          TurnaIconId.play,
          size: 18,
          color: TurnaTheme.textOnPrimary,
        ),
        label: Text(AppStrings.ankiReviewAll, style: AppTextStyles.buttonLabel),
      ),
    );
  }
}

class _AnkiSectionCard extends StatelessWidget {
  final int index;
  final String sectionId;
  final String sectionName;
  final String description;
  final int? dueCount;
  final VoidCallback onTap;
  final VoidCallback? onStats;
  final VoidCallback? onBrowse;
  final VoidCallback onPin;

  const _AnkiSectionCard({
    required this.index,
    required this.sectionId,
    required this.sectionName,
    required this.description,
    required this.dueCount,
    required this.onTap,
    required this.onStats,
    required this.onBrowse,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    final accent = TurnaTheme.accentOnCard(context, TurnaTheme.brandSky);
    final hasDue = dueCount == null || dueCount! > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassSurface(
        accent: TurnaTheme.brandSky,
        level: GlassLevel.l1Subtle,
        radius: TurnaTheme.borderRadius,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          14,
          AppSpacing.xs,
          10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: TurnaIcon(
                      TurnaIconId.dragHandle,
                      size: 18,
                      color: TurnaTheme.textHintColor(context),
                    ),
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: TurnaTheme.softTint(context, accent, alpha: 0.12),
                    borderRadius: TurnaTheme.borderRadius,
                  ),
                  child: TurnaIcon(TurnaIconId.cards, color: accent, size: 18),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sectionName,
                        style: AppTextStyles.cardTitle(context),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: AppTextStyles.captionSm(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (hasDue) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm + 2,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: const BoxDecoration(
                      color: TurnaTheme.brandTeal,
                      borderRadius: TurnaTheme.borderRadius,
                    ),
                    child: Text(
                      dueCount?.toString() ?? '—',
                      style: AppTextStyles.caption(context).copyWith(
                        color: TurnaTheme.textOnPrimary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                TurnaIcon(
                  TurnaIconId.chevronRight,
                  size: 16,
                  color: accent.withValues(alpha: 0.7),
                ),
                _DeckMenuButton(
                  onStats: onStats,
                  onBrowse: onBrowse,
                  onPin: onPin,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Row(
                children: [
                  if (onBrowse != null)
                    TextButton.icon(
                      onPressed: onBrowse,
                      icon: const TurnaIcon(TurnaIconId.list, size: 15),
                      label: Text(AppStrings.ankiBrowseCards),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: TurnaTheme.textSecondaryColor(context),
                      ),
                    ),
                  if (onStats != null)
                    TextButton.icon(
                      onPressed: onStats,
                      icon: const TurnaIcon(TurnaIconId.insights, size: 15),
                      label: Text(AppStrings.ankiDeckStats),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: TurnaTheme.textSecondaryColor(context),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeckMenuButton extends StatelessWidget {
  final VoidCallback? onStats;
  final VoidCallback? onBrowse;
  final VoidCallback onPin;

  const _DeckMenuButton({
    required this.onStats,
    required this.onBrowse,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: TurnaIcon(
        TurnaIconId.moreVert,
        size: 18,
        color: TurnaTheme.textSecondaryColor(context),
      ),
      padding: const EdgeInsets.all(AppSpacing.xs),
      tooltip: '',
      itemBuilder: (context) => [
        if (onStats != null)
          PopupMenuItem<String>(
            value: 'stats',
            child: Row(
              children: [
                const TurnaIcon(TurnaIconId.insights, size: 18),
                const SizedBox(width: AppSpacing.md),
                Text(AppStrings.ankiDeckStats),
              ],
            ),
          ),
        if (onBrowse != null)
          PopupMenuItem<String>(
            value: 'browse',
            child: Row(
              children: [
                const TurnaIcon(TurnaIconId.list, size: 18),
                const SizedBox(width: AppSpacing.md),
                Text(AppStrings.ankiBrowseCards),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'pin',
          child: Row(
            children: [
              const TurnaIcon(TurnaIconId.pin, size: 18),
              const SizedBox(width: AppSpacing.md),
              Text(AppStrings.ankiPinDeck),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        if (value == 'stats') onStats?.call();
        if (value == 'browse') onBrowse?.call();
        if (value == 'pin') onPin();
      },
    );
  }
}
