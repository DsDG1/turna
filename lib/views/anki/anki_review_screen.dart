// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/anki/anki_review_assembler.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/anki/anki_card_browser_page.dart';
import 'package:turna/views/anki/anki_deck_stats_page.dart';
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

class _AnkiReviewBody extends StatelessWidget {
  const _AnkiReviewBody();

  @override
  Widget build(BuildContext context) {
    final courseProvider = context.watch<CourseProvider>();
    final srsProvider = context.watch<SrsProvider>();

    // Find Anki sections (allSections: the review hub lists decks even when
    // the course scope hides them from the Learn-page tree).
    final ankiSections =
        courseProvider.allSections.where((s) => s.level == 'Anki').toList();

    final deckOrder = {
      for (var i = 0; i < courseProvider.courseEntries.length; i++)
        courseProvider.courseEntries[i].scope: i,
    };
    ankiSections.sort((a, b) => (deckOrder[_scopeForSection(a.id)] ?? 9999)
        .compareTo(deckOrder[_scopeForSection(b.id)] ?? 9999));

    if (ankiSections.isEmpty) {
      return _buildEmptyState(context);
    }

    final assembler = AnkiReviewAssembler(srsProvider, courseProvider,
        noteDao: getIt<AnkiNoteDao>());
    // One pass over the SRS map for total + per-import due badges (not one
    // full collectDue sort per section tile).
    final dueSnap = assembler.dueSnapshot();
    final totalDue = dueSnap.total;
    final deckManager = getIt<AnkiDeckManager>();
    final newLeft = deckManager.newRemainingToday;
    final reviewLeft = deckManager.reviewRemainingToday;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Daily quota summary
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: TurnaTheme.cardBg(context),
            borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            border: Border.all(
              color: TurnaTheme.peacockTeal.withValues(alpha: 0.12),
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
        if (totalDue > 0)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: TurnaTheme.peacockTeal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active,
                    color: TurnaTheme.peacockTeal),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppStrings.ankiCardsDueReview(totalDue),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: TurnaTheme.peacockTeal,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _startReview(context, null),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TurnaTheme.peacockTeal,
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
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ankiSections.length,
          onReorder: (oldIndex, newIndex) =>
              _reorderDecks(context, ankiSections, oldIndex, newIndex),
          itemBuilder: (context, index) {
            final section = ankiSections[index];
            return KeyedSubtree(
              key: ValueKey(section.id),
              child: _AnkiSectionCard(
                sectionId: section.id,
                sectionName: section.name,
                description: section.description,
                dueCount: dueSnap.byImportId[
                        AnkiReviewAssembler.importIdFromSectionId(
                            section.id)] ??
                    0,
                onTap: () => _startReview(context, section.id),
                onStats: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AnkiDeckStatsPage(
                      importId: AnkiReviewAssembler.importIdFromSectionId(
                        section.id,
                      ),
                      title: section.name,
                    ),
                  ),
                ),
                onBrowse: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AnkiCardBrowserPage(
                      importId: AnkiReviewAssembler.importIdFromSectionId(
                        section.id,
                      ),
                      title: section.name,
                      sectionId: section.id,
                    ),
                  ),
                ),
                onPin: () => _pinDeck(context, section.id),
                onOptions: () => _editDeckOptions(
                  context,
                  sectionId: section.id,
                  title: section.name,
                ),
                onUninstall: () => _confirmUninstall(
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

  static String _scopeForSection(String sectionId) =>
      'anki:${AnkiReviewAssembler.importIdFromSectionId(sectionId)}';

  Future<void> _reorderDecks(
      BuildContext context, List sections, int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex--;
    final reordered = List.of(sections);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    final deckIds = <String>{
      for (final section in reordered)
        AnkiReviewAssembler.importIdFromSectionId(section.id),
    };
    final allScopes = context
        .read<CourseProvider>()
        .courseEntries
        .map((entry) => entry.scope)
        .where((scope) =>
            !scope.startsWith('anki:') || deckIds.contains(scope.substring(5)))
        .toList();
    final builtIn = allScopes.where((scope) => scope.isEmpty);
    final others = allScopes.where((scope) => scope.isNotEmpty).toSet();
    await context.read<CourseProvider>().persistCourseOrder([
      ...builtIn,
      for (final section in reordered)
        'anki:${AnkiReviewAssembler.importIdFromSectionId(section.id)}',
      ...others.where((scope) =>
          !reordered.any((section) => scope == _scopeForSection(section.id))),
    ]);
  }

  Future<void> _pinDeck(BuildContext context, String sectionId) async {
    final pinned = _scopeForSection(sectionId);
    final scopes = context
        .read<CourseProvider>()
        .courseEntries
        .map((entry) => entry.scope)
        .where((scope) => scope != pinned)
        .toList();
    final at = scopes.indexOf('');
    scopes.insert(at < 0 ? 0 : at + 1, pinned);
    await context.read<CourseProvider>().persistCourseOrder(scopes);
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
    await getIt<AnkiDeckManager>().uninstallDeck(importId);
    if (!context.mounted) return;
    final courseProvider = context.read<CourseProvider>();
    if (courseProvider.courseScope == 'anki:$importId') {
      // The active scope pointed at the removed deck — fall back to the
      // built-in course (setCourseScope reloads the tree itself).
      await courseProvider.setCourseScope('');
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
              color: TurnaTheme.peacockTeal.withValues(alpha: 0.4),
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
                backgroundColor: TurnaTheme.peacockTeal,
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

  void _startReview(BuildContext context, String? sectionId) {
    context.router.push(AnkiReviewSessionRoute(sectionId: sectionId));
  }
}

class _AnkiSectionCard extends StatelessWidget {
  final String sectionId;
  final String sectionName;
  final String description;
  final int dueCount;
  final VoidCallback onTap;
  final VoidCallback onStats;
  final VoidCallback onBrowse;
  final VoidCallback onPin;
  final VoidCallback onOptions;
  final VoidCallback onUninstall;

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
                color: TurnaTheme.peacockTeal.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TurnaTheme.peacockTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.layers_rounded,
                    color: TurnaTheme.peacockTeal,
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
                if (dueCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: TurnaTheme.peacockTeal,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$dueCount',
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
                  color: TurnaTheme.peacockTeal.withValues(alpha: 0.5),
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
  final VoidCallback onStats;
  final VoidCallback onBrowse;
  final VoidCallback onPin;
  final VoidCallback onOptions;
  final VoidCallback onUninstall;

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
        if (value == 'stats') onStats();
        if (value == 'browse') onBrowse();
        if (value == 'pin') onPin();
        if (value == 'options') onOptions();
        if (value == 'uninstall') onUninstall();
      },
    );
  }
}
