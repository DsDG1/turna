// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/anki/anki_deck_manager.dart';
import 'package:varnamala/application/anki/anki_review_assembler.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/data/anki_import_dao.dart';
import 'package:varnamala/data/course_database.dart';
import 'package:varnamala/data/course_repository.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/l10n/app_localizations.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/views/theme.dart';

/// Anki review hub — lists imported Anki sections with due counts,
/// allows starting a review session for a selected section.
@RoutePage()
class AnkiReviewPage extends StatelessWidget {
  const AnkiReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.ankiReviewScreenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.router.maybePop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: AppLocalizations.of(context)!.ankiImportNewDeck,
            onPressed: () => context.router.push(const AnkiImportRoute()),
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

    // Find Anki sections
    final ankiSections = courseProvider.sections
        .where((s) => s.level == 'Anki')
        .toList();

    if (ankiSections.isEmpty) {
      return _buildEmptyState(context);
    }

    final assembler = AnkiReviewAssembler(srsProvider, courseProvider);
    final totalDue = assembler.totalAnkiDueCount;
    final deckManager = AnkiDeckManager(
      repo: CourseRepository(getIt<CourseDatabase>()),
      srsProvider: srsProvider,
      importDao: AnkiImportDao(getIt<CourseDatabase>()),
      appPrefs: getIt<AppPrefs>(),
    );
    final newLeft = deckManager.newRemainingToday;
    final reviewLeft = deckManager.reviewRemainingToday;
    final l10n = AppLocalizations.of(context)!;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Daily quota summary
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: VarnamalaTheme.cardBg(context),
            borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
            border: Border.all(
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.today_rounded,
                size: 18,
                color: VarnamalaTheme.textSecondaryColor(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (newLeft == 0 && reviewLeft == 0)
                      ? l10n.ankiQuotaExhausted
                      : l10n.ankiQuotaRemaining(newLeft, reviewLeft),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: VarnamalaTheme.textSecondaryColor(context),
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
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active,
                    color: VarnamalaTheme.peacockTeal),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.ankiCardsDueReview(totalDue),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: VarnamalaTheme.peacockTeal,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _startReview(context, null),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VarnamalaTheme.peacockTeal,
                    foregroundColor: VarnamalaTheme.textOnPrimary,
                  ),
                  child: Text(AppLocalizations.of(context)!.ankiReviewAll),
                ),
              ],
            ),
          ),

        // Section list
        for (final section in ankiSections)
          _AnkiSectionCard(
            sectionId: section.id,
            sectionName: section.name,
            description: section.description,
            dueCount: assembler.dueCount(sectionId: section.id),
            onTap: () => _startReview(context, section.id),
            onUninstall: () => _confirmUninstall(
              context,
              sectionId: section.id,
              sectionName: section.name,
            ),
          ),
      ],
    );
  }

  Future<void> _confirmUninstall(
    BuildContext context, {
    required String sectionId,
    required String sectionName,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.ankiUninstallConfirmTitle),
        content: Text('$sectionName\n\n${l10n.ankiUninstallConfirmBody}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: VarnamalaTheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.ankiUninstallDeck),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final importId = AnkiReviewAssembler.importIdFromSectionId(sectionId);
    if (importId.isEmpty) return;
    final deckManager = AnkiDeckManager(
      repo: CourseRepository(getIt<CourseDatabase>()),
      srsProvider: context.read<SrsProvider>(),
      importDao: AnkiImportDao(getIt<CourseDatabase>()),
      appPrefs: getIt<AppPrefs>(),
    );
    await deckManager.uninstallDeck(importId);
    if (!context.mounted) return;
    await context.read<CourseProvider>().reloadCourse();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.ankiDeckRemoved)),
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
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.ankiNoDecksTitle,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.ankiNoDecksSubtitle,
              style: TextStyle(
                color: VarnamalaTheme.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => context.router.push(const AnkiImportRoute()),
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context)!.ankiImportDeck),
              style: ElevatedButton.styleFrom(
                backgroundColor: VarnamalaTheme.peacockTeal,
                foregroundColor: VarnamalaTheme.textOnPrimary,
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
  final VoidCallback onUninstall;

  const _AnkiSectionCard({
    required this.sectionId,
    required this.sectionName,
    required this.description,
    required this.dueCount,
    required this.onTap,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
              border: Border.all(
                color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        VarnamalaTheme.peacockTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.layers_rounded,
                    color: VarnamalaTheme.peacockTeal,
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
                          color: VarnamalaTheme.textSecondaryColor(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (dueCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: VarnamalaTheme.peacockTeal,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$dueCount',
                      style: const TextStyle(
                        color: VarnamalaTheme.textOnPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                _UninstallMenuButton(onUninstall: onUninstall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UninstallMenuButton extends StatelessWidget {
  final VoidCallback onUninstall;

  const _UninstallMenuButton({required this.onUninstall});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: VarnamalaTheme.textSecondaryColor(context),
      ),
      padding: const EdgeInsets.all(4),
      tooltip: '',
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'uninstall',
          child: Row(
            children: [
              const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: VarnamalaTheme.error,
              ),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(context)!.ankiUninstallDeck),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        if (value == 'uninstall') onUninstall();
      },
    );
  }
}
