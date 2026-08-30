import 'package:flutter/material.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
import 'package:turna/views/theme.dart';

/// Done step (maintainability plan §10.5): renders the unified
/// [AnkiImportSummary] and the completion actions. "完成" pops without
/// switching courses; "立即学习" is the ONLY action that switches (plan 34
/// R1-4) — both are forwarded as page-level intents.
class AnkiImportDoneStep extends StatelessWidget {
  const AnkiImportDoneStep({
    super.key,
    required this.summary,
    required this.keptLearningProgress,
    required this.onStartLearningNow,
    required this.onViewDecks,
    required this.onDone,
  });

  final AnkiImportSummary summary;
  final bool keptLearningProgress;
  final VoidCallback onStartLearningNow;
  final VoidCallback onViewDecks;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Center(
              child: Icon(
                Icons.check_circle_outline,
                size: 72,
                color: TurnaTheme.success,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                AppStrings.ankiImportComplete,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                AppStrings.ankiDoneSummary(summary.cardCount),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: TurnaTheme.brandTeal,
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  summary.lessonCount > 0
                      ? AppStrings.ankiLessonsCreated(summary.lessonCount)
                      : AppStrings.anki21bTreeDeferred,
                  style: TextStyle(
                    fontSize: 13,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            DoneGroup(
              title: AppStrings.ankiDoneGroupSource,
              rows: [
                AppStrings.ankiImportSourceCards(summary.sourceCardCount),
                // Doc 39 F2: the "0 structured / 0 fidelity" rows were
                // removed — official-first never filled those Legacy
                // parser counters, so users always saw two zero rows.
              ],
            ),
            if (summary.wordEntryCount > 0) ...[
              const SizedBox(height: 12),
              DoneGroup(
                title: AppStrings.ankiDoneGroupVocab,
                rows: [
                  AppStrings.ankiVocabAdded(summary.wordEntryCount),
                ],
              ),
            ],
            // Status notes: only show non-zero warnings so a clean import
            // does not list "0 missing media" / "0 buried" etc.
            if (summary.unknownTemplateCount > 0 ||
                summary.suspendedCardCount > 0 ||
                summary.buriedCardCount > 0 ||
                summary.missingMediaCount > 0 ||
                summary.failedMediaCount > 0) ...[
              const SizedBox(height: 12),
              DoneGroup(
                title: AppStrings.ankiDoneGroupStatus,
                rows: [
                  if (summary.unknownTemplateCount > 0)
                    AppStrings.ankiImportUnknownTemplates(
                        summary.unknownTemplateCount),
                  if (summary.suspendedCardCount > 0)
                    AppStrings.ankiImportSuspended(
                        summary.suspendedCardCount),
                  if (summary.buriedCardCount > 0)
                    AppStrings.ankiImportBuried(summary.buriedCardCount),
                  if (summary.missingMediaCount > 0 ||
                      summary.failedMediaCount > 0)
                    AppStrings.ankiImportMissingMedia(
                        summary.missingMediaCount + summary.failedMediaCount),
                ],
              ),
            ],
            const SizedBox(height: 12),
            LearningProgressBadge(
              kept: keptLearningProgress,
              hasScheduling: summary.hasScheduling,
              hasReviewHistory: summary.hasReviewHistory,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onStartLearningNow,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(
                AppStrings.ankiStartLearning,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: TurnaTheme.brandTeal,
                foregroundColor: TurnaTheme.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Secondary action: open course management with the new course
            // highlighted (switch / reorder / inspect) — a distinct
            // destination from "Done", which simply returns (plan 34 R1-4).
            OutlinedButton.icon(
              onPressed: onViewDecks,
              icon: const Icon(Icons.list_alt_rounded, size: 18),
              label: Text(AppStrings.ankiDoneViewDecks),
              style: OutlinedButton.styleFrom(
                foregroundColor: TurnaTheme.brandTeal,
                side: const BorderSide(color: TurnaTheme.brandTeal),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: onDone,
              child: Text(AppStrings.commonDone),
            ),
          ],
        ),
      ),
    );
  }
}
