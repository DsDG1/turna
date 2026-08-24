// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/anki/anki_review_assembler.dart';
import 'package:turna/application/anki/formal_review_launcher.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due_sync.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/theme.dart';

/// Anki review hub — lists imported Anki sections with due counts,
/// allows starting a review session for a selected section.
@RoutePage()
class AnkiReviewPage extends StatelessWidget {
  const AnkiReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.ankiReviewScreenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.router.maybePop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
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
    final srsProvider = context.watch<SrsProvider>();

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
      (a, b) => (deckOrder[wireForImportId[AnkiReviewAssembler
              .importIdFromSectionId(a.id)]] ??
              9999)
          .compareTo(
              deckOrder[wireForImportId[AnkiReviewAssembler
                      .importIdFromSectionId(b.id)]] ??
                  9999),
    );

    if (ankiSections.isEmpty) {
      return _buildEmptyState(context);
    }

    final assembler = AnkiReviewAssembler(srsProvider, courseProvider,
        noteDao: getIt<AnkiNoteDao>());
    // One pass over the SRS map for total + per-import due badges (not one
    // full collectDue sort per section tile).
    final dueSnap = assembler.dueSnapshot();
    final totalDue = _aggregatedDue(ankiSections, dueSnap.byImportId);
    final unintroducedNew = assembler.unintroducedDueCount() +
        OfficialAnkiHomeDue.unintroducedOfficialDue;
    final hasLegacySections = ankiSections.any((section) {
      final importId = AnkiReviewAssembler.importIdFromSectionId(section.id);
      return !OfficialAnkiHomeDue.officialImportIds.contains(importId);
    });
    final deckManager = getIt<AnkiDeckManager>();
    final newLeft = deckManager.newRemainingToday;
    final reviewLeft = deckManager.reviewRemainingToday;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Daily quota summary
        if (hasLegacySections)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: TurnaTheme.cardBg(context),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
              border: Border.all(
                color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.today_rounded,
                  size: 18,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (newLeft == 0 && reviewLeft == 0)
                        ? AppStrings.ankiQuotaExhausted
                        : AppStrings.ankiQuotaRemaining(newLeft, reviewLeft),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Total due summary
        if (OfficialAnkiHomeDue.officialDueUnavailable)
          Container(
            key: const Key('anki-due-unavailable'),
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: TurnaTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            ),
            child: Row(
              children: [
                const Icon(Icons.sync_problem_rounded,
                    color: TurnaTheme.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppStrings.ankiDueUnavailable,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: AppStrings.ankiReviewRetry,
                  onPressed: _refreshOfficialDue,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          )
        else if (totalDue > 0 || unintroducedNew > 0)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active,
                    color: TurnaTheme.brandTeal),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppStrings.ankiFormalDueBreakdown(
                      introducedDue: totalDue,
                      unintroducedNew: unintroducedNew,
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: TurnaTheme.brandTeal,
                    ),
                  ),
                ),
                if (totalDue > 0)
                  ElevatedButton(
                    // Review All (plan 34 R2-3): a null section id plans a
                    // session across EVERY official source's formal due
                    // set — never just the first source with due cards.
                    onPressed: () => _startReview(
                      context,
                      null,
                      entry: FormalReviewEntryKind.courseReview,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TurnaTheme.brandTeal,
                      foregroundColor: TurnaTheme.textOnPrimary,
                    ),
                    child: Text(AppStrings.ankiReviewAll),
                  ),
              ],
            ),
          ),

        // Section list. The order is persisted in the same course-order
        // preference used by the course-management screen.
        ReorderableListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ankiSections.length,
          onReorderItem: (oldIndex, newIndex) =>
              _reorderDecks(context, ankiSections, oldIndex, newIndex),
          itemBuilder: (context, index) {
            final section = ankiSections[index];
            final importId = AnkiReviewAssembler.importIdFromSectionId(
              section.id,
            );
            final isOfficial =
                OfficialAnkiHomeDue.officialImportIds.contains(importId);
            return KeyedSubtree(
              key: ValueKey(section.id),
              child: _AnkiSectionCard(
                sectionId: section.id,
                sectionName: section.name,
                description: section.description,
                dueCount: _dueForSection(
                  importId,
                  dueSnap.byImportId,
                ),
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
                onOptions: isOfficial
                    ? null
                    : () => _editDeckOptions(
                          context,
                          sectionId: section.id,
                          title: section.name,
                        ),
                onUninstall: isOfficial
                    ? null
                    : () => _confirmUninstall(
                          context,
                          sectionId: section.id,
                          sectionName: section.name,
                        ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _reorderDecks(
      BuildContext context, List sections, int oldIndex, int newIndex) async {
    final provider = context.read<CourseProvider>();
    final reordered = List.of(sections);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    final deckIds = <String>{
      for (final section in reordered)
        AnkiReviewAssembler.importIdFromSectionId((section as dynamic).id
            as String),
    };
    // Wire-key based reorder: keep builtin first, then the decks in the
    // user's drag order, then any non-deck courses untouched.
    final wireForId = <String, String>{};
    for (final entry in provider.catalogEntries) {
      final id = entry.legacyImportId ?? entry.officialSourceId;
      if (id != null) wireForId[id] = entry.wireKey;
    }
    final reorderedWires = <String>{
      for (final id in deckIds)
        if (wireForId[id] != null) wireForId[id]!,
    };
    final order = <String>[];
    for (final entry in provider.catalogEntries) {
      if (entry.isBuiltin) {
        order.add(entry.wireKey);
      } else if (reorderedWires.contains(entry.wireKey)) {
        // Deck section order handled below.
        continue;
      } else {
        order.add(entry.wireKey);
      }
    }
    // Splice the dragged deck order right after the builtin course.
    final builtinWire = const BuiltinCourseScope('turkish').wireKey;
    final builtinIndex = order.indexOf(builtinWire);
    order.insertAll(
      builtinIndex < 0 ? order.length : builtinIndex + 1,
      reorderedWires.toList(),
    );
    await provider.persistCourseOrder(order);
  }

  Future<void> _pinDeck(BuildContext context, String sectionId) async {
    final provider = context.read<CourseProvider>();
    final importId = AnkiReviewAssembler.importIdFromSectionId(sectionId);
    final pinnedWire = provider.catalogEntries
        .where((entry) =>
            entry.legacyImportId == importId ||
            entry.officialSourceId == importId)
        .map((entry) => entry.wireKey)
        .firstOrNull;
    if (pinnedWire == null) return;
    final wires = provider.catalogEntries
        .map((entry) => entry.wireKey)
        .where((wire) => wire != pinnedWire)
        .toList();
    final builtinWire = const BuiltinCourseScope('turkish').wireKey;
    final at = wires.indexOf(builtinWire);
    wires.insert(at < 0 ? 0 : at + 1, pinnedWire);
    await provider.persistCourseOrder(wires);
  }

  Future<void> _editDeckOptions(
    BuildContext context, {
    required String sectionId,
    required String title,
  }) async {
    final importId = AnkiReviewAssembler.importIdFromSectionId(sectionId);
    final dao = getIt<AnkiImportDao>();
    final currentNew = await dao.dailyNewLimitFor(importId);
    final currentReview = await dao.dailyReviewLimitFor(importId);
    if (!context.mounted) return;
    final newController = TextEditingController(
      text: currentNew?.toString() ?? '',
    );
    final reviewController = TextEditingController(
      text: currentReview?.toString() ?? '',
    );
    final result = await showDialog<({int? newLimit, int? reviewLimit})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$title · 牌组设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '每日新卡上限',
                hintText: '留空使用全局上限',
              ),
            ),
            TextField(
              controller: reviewController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '每日复习上限',
                hintText: '留空使用全局上限',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              (
                newLimit: int.tryParse(newController.text.trim()),
                reviewLimit: int.tryParse(reviewController.text.trim()),
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    newController.dispose();
    reviewController.dispose();
    if (result == null || !context.mounted) return;
    await dao.setDailyLimits(
      importId,
      newLimit: result.newLimit,
      reviewLimit: result.reviewLimit,
    );
  }

  Future<void> _confirmUninstall(
    BuildContext context, {
    required String sectionId,
    required String sectionName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.ankiUninstallConfirmTitle),
        content: Text('$sectionName\n\n${AppStrings.ankiUninstallConfirmBody}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: TurnaTheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppStrings.ankiUninstallDeck),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final importId = AnkiReviewAssembler.importIdFromSectionId(sectionId);
    if (importId.isEmpty) return;
    await getIt<AnkiDeckManager>().uninstall(importId);
    if (!context.mounted) return;
    final courseProvider = context.read<CourseProvider>();
    final removedWasActive = courseProvider.catalogEntries.any((entry) =>
        (entry.legacyImportId == importId ||
            entry.officialSourceId == importId) &&
        entry.wireKey == courseProvider.courseScope);
    if (removedWasActive) {
      // The active scope pointed at the removed course — fall back to the
      // built-in course (setScope reloads the tree itself).
      await courseProvider.setScope(const BuiltinCourseScope('turkish'));
    } else {
      await courseProvider.reloadCourse();
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.ankiDeckRemoved)),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.layers_outlined,
              size: 80,
              color: TurnaTheme.brandTeal.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 24),
            Text(
              AppStrings.ankiNoDecksTitle,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.ankiNoDecksSubtitle,
              style: TextStyle(
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => context.router.push(AnkiImportRoute()),
              icon: const Icon(Icons.add),
              label: Text(AppStrings.ankiImportDeck),
              style: ElevatedButton.styleFrom(
                backgroundColor: TurnaTheme.brandTeal,
                foregroundColor: TurnaTheme.textOnPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int? _dueForSection(String importId, Map<String, int> byImportId) {
    if (OfficialAnkiHomeDue.officialImportIds.contains(importId)) {
      if (OfficialAnkiHomeDue.officialDueUnavailable) return null;
      return OfficialAnkiHomeDue.formalOfficialDueForImport(importId);
    }
    return byImportId[importId] ?? 0;
  }

  int _aggregatedDue(
    List<dynamic> ankiSections,
    Map<String, int> byImportId,
  ) {
    var total = 0;
    for (final section in ankiSections) {
      total += _dueForSection(
            AnkiReviewAssembler.importIdFromSectionId(section.id as String),
            byImportId,
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
        : AnkiReviewAssembler.importIdFromSectionId(sectionId);
    await const FormalReviewLauncher().open(
      context,
      entry: entry,
      courseId: importId.isEmpty ? 'anki' : 'anki-$importId',
      sectionId: sectionId,
      officialOwner:
          OfficialAnkiHomeDue.officialImportIds.contains(importId),
      schedulerRuntimeAvailable:
          OfficialAnkiFeatureFlags.current.allowsOfficialScheduler,
    );
  }
}

class _AnkiSectionCard extends StatelessWidget {
  final String sectionId;
  final String sectionName;
  final String description;
  final int? dueCount;
  final VoidCallback onTap;
  final VoidCallback? onStats;
  final VoidCallback? onBrowse;
  final VoidCallback onPin;
  final VoidCallback? onOptions;
  final VoidCallback? onUninstall;

  const _AnkiSectionCard({
    required this.sectionId,
    required this.sectionName,
    required this.description,
    required this.dueCount,
    required this.onTap,
    required this.onStats,
    required this.onBrowse,
    required this.onPin,
    required this.onOptions,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
              border: Border.all(
                color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.layers_rounded,
                    color: TurnaTheme.brandTeal,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sectionName,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
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
                  ),
                ),
                if (dueCount == null || dueCount! > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: TurnaTheme.brandTeal,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      dueCount?.toString() ?? '—',
                      style: const TextStyle(
                        color: TurnaTheme.textOnPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                _UninstallMenuButton(
                  onStats: onStats,
                  onBrowse: onBrowse,
                  onPin: onPin,
                  onOptions: onOptions,
                  onUninstall: onUninstall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UninstallMenuButton extends StatelessWidget {
  final VoidCallback? onStats;
  final VoidCallback? onBrowse;
  final VoidCallback onPin;
  final VoidCallback? onOptions;
  final VoidCallback? onUninstall;

  const _UninstallMenuButton({
    required this.onStats,
    required this.onBrowse,
    required this.onPin,
    required this.onOptions,
    required this.onUninstall,
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
          const PopupMenuItem<String>(
            value: 'stats',
            child: Row(
              children: [
                Icon(Icons.insights_outlined, size: 20),
                SizedBox(width: 12),
                Text('统计'),
              ],
            ),
          ),
        if (onBrowse != null)
          const PopupMenuItem<String>(
            value: 'browse',
            child: Row(
              children: [
                Icon(Icons.view_list_outlined, size: 20),
                SizedBox(width: 12),
                Text('浏览卡片'),
              ],
            ),
          ),
        const PopupMenuItem<String>(
          value: 'pin',
          child: Row(
            children: [
              Icon(Icons.push_pin_outlined, size: 20),
              SizedBox(width: 12),
              Text('置顶'),
            ],
          ),
        ),
        if (onOptions != null)
          const PopupMenuItem<String>(
            value: 'options',
            child: Row(
              children: [
                Icon(Icons.tune_outlined, size: 20),
                SizedBox(width: 12),
                Text('牌组设置'),
              ],
            ),
          ),
        if (onUninstall != null)
          PopupMenuItem<String>(
            value: 'uninstall',
            child: Row(
              children: [
                const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: TurnaTheme.error,
                ),
                const SizedBox(width: 12),
                Text(AppStrings.ankiUninstallDeck),
              ],
            ),
          ),
      ],
      onSelected: (value) {
        if (value == 'stats') onStats?.call();
        if (value == 'browse') onBrowse?.call();
        if (value == 'pin') onPin();
        if (value == 'options') onOptions?.call();
        if (value == 'uninstall') onUninstall?.call();
      },
    );
  }
}
