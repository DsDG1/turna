// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due_sync.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/widgets/turna_cards.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';

/// Anki review hub — lists imported Anki sections with due counts,
/// allows starting a review session for a selected section.
@RoutePage()
class AnkiReviewPage extends StatelessWidget {
  const AnkiReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(AppStrings.ankiReviewScreenTitle),
        leading: IconButton(
          tooltip: AppStrings.commonBack,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.router.maybePop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton.filledTonal(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: AppStrings.ankiImportNewDeck,
              onPressed: () => context.router.push(AnkiImportRoute()),
            ),
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
      final id = entry.legacyImportId ?? entry.officialSourceId;
      if (id != null) wireForImportId[id] = entry.wireKey;
    }
    final deckOrder = {
      for (var i = 0; i < courseProvider.catalogEntries.length; i++)
        courseProvider.catalogEntries[i].wireKey: i,
    };
    ankiSections.sort(
      (a, b) => (deckOrder[wireForImportId[
                  LegacyAnkiIdentifiers.importIdFromSectionId(a.id)]] ??
              9999)
          .compareTo(deckOrder[wireForImportId[
                  LegacyAnkiIdentifiers.importIdFromSectionId(b.id)]] ??
              9999),
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          sliver: SliverToBoxAdapter(
            child: SectionTitle(title: AppStrings.ankiHubDecksTitle),
          ),
        ),
        // Section list. The order is persisted in the same course-order
        // preference used by the course-management screen.
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
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
                    onStats: () => context.router.push(AnkiDeckStatsRoute(
                      importId: importId,
                      title: section.name,
                    )),
                    onBrowse: () => context.router.push(AnkiCardBrowserRoute(
                      importId: importId,
                      title: section.name,
                      sectionId: section.id,
                    )),
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
    if (OfficialFormalDueRepository.instance.officialImportIds
        .contains(importId)) {
      if (OfficialFormalDueRepository.instance.snapshot.unavailable) {
        return null;
      }
      return OfficialFormalDueRepository.instance
          .formalOfficialDueForImport(importId);
    }
    // Legacy-owned section: scheduler retired (doc 35 L2), nothing is due.
    return 0;
  }

  int _aggregatedDue(List<Section> ankiSections) {
    var total = 0;
    for (final section in ankiSections) {
      total += _dueForSection(
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
    return SoftCard(
      key: const Key('anki-due-unavailable'),
      accentColor: TurnaTheme.warning,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          children: [
            AccentIconChip(
              icon: Icons.sync_problem_rounded,
              color: TurnaTheme.warning,
              size: 22,
              padding: 8,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppStrings.ankiDueUnavailable,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            IconButton(
              tooltip: AppStrings.ankiReviewRetry,
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
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

    const radius = BorderRadius.all(Radius.circular(TurnaTheme.cardRadius));
    return Semantics(
      button: onReviewAll != null,
      label: AppStrings.ankiReviewAll,
      child: Material(
        key: const Key('anki-review-hub-hero'),
        color: Colors.transparent,
        child: InkWell(
          onTap: onReviewAll,
          borderRadius: radius,
          child: Ink(
            decoration: TurnaTheme.brandHeroDecoration(
              context,
              borderRadius: radius,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AnkiDueHeroHeader(
                    introducedDue: introducedDue,
                    unintroducedNew: unintroducedNew,
                  ),
                  if (onReviewAll != null) ...[
                    const SizedBox(height: 16),
                    _AnkiReviewAllButton(onPressed: onReviewAll!),
                  ],
                ],
              ),
            ),
          ),
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
    return SoftCard(
      key: const Key('anki-review-hub-caught-up'),
      accentColor: TurnaTheme.brandTeal,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.ankiHubCaughtUpTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.ankiHubCaughtUpMessage,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TurnaTheme.textSecondaryColor(context),
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
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(TurnaTheme.cardRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.24),
            ),
          ),
          child: const Icon(
            Icons.style_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.ankiReviewScreenTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                AppStrings.ankiFormalDueBreakdown(
                  introducedDue: introducedDue,
                  unintroducedNew: unintroducedNew,
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$introducedDue',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.1,
                  ),
            ),
            Text(
              AppStrings.ankiHubDueCountLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
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
      height: 44,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: TurnaTheme.brandTeal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(
          AppStrings.ankiReviewAll,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        accentColor: TurnaTheme.brandSky,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: TurnaTheme.textHintColor(context),
                      ),
                    ),
                  ),
                  AccentIconChip(
                    icon: Icons.style_rounded,
                    color: accent,
                    size: 22,
                    padding: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sectionName,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 13,
                              color: TurnaTheme.textSecondaryColor(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (hasDue) ...[
                    CountBadge(
                      label: dueCount?.toString() ?? '—',
                      color: TurnaTheme.brandTeal,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: accent.withValues(alpha: 0.7),
                  ),
                  _DeckMenuButton(
                    onStats: onStats,
                    onBrowse: onBrowse,
                    onPin: onPin,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  children: [
                    if (onBrowse != null)
                      TextButton.icon(
                        onPressed: onBrowse,
                        icon: const Icon(Icons.view_list_outlined, size: 16),
                        label: Text(AppStrings.ankiBrowseCards),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor:
                              TurnaTheme.textSecondaryColor(context),
                        ),
                      ),
                    if (onStats != null)
                      TextButton.icon(
                        onPressed: onStats,
                        icon: const Icon(Icons.insights_outlined, size: 16),
                        label: Text(AppStrings.ankiDeckStats),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor:
                              TurnaTheme.textSecondaryColor(context),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
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
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: TurnaTheme.textSecondaryColor(context),
      ),
      padding: const EdgeInsets.all(4),
      tooltip: '',
      itemBuilder: (context) => [
        if (onStats != null)
          PopupMenuItem<String>(
            value: 'stats',
            child: Row(
              children: [
                const Icon(Icons.insights_outlined, size: 20),
                const SizedBox(width: 12),
                Text(AppStrings.ankiDeckStats),
              ],
            ),
          ),
        if (onBrowse != null)
          PopupMenuItem<String>(
            value: 'browse',
            child: Row(
              children: [
                const Icon(Icons.view_list_outlined, size: 20),
                const SizedBox(width: 12),
                Text(AppStrings.ankiBrowseCards),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'pin',
          child: Row(
            children: [
              const Icon(Icons.push_pin_outlined, size: 20),
              const SizedBox(width: 12),
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
