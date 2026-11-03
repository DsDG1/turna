import 'package:flutter/material.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/core/theme.dart';

/// Done step (maintainability plan §10.5), 步骤流程版式（ADR 0066）：中央
/// 摘要（统一 [AnkiImportSummary] 的分组明细），底部固定动作带。
///
/// 动作口径（ADR 0066 §2）：「立即学习」直接进入该牌组的正式复习，**不再
/// 切换当前语言课程**；「查看牌组」指向记忆卡中枢；「完成」仅返回。三个
/// 动作都是页面级意图，由宿主页面接线。
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
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageMargin,
              AppSpacing.xl,
              AppSpacing.pageMargin,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: TurnaTheme.success,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: Text(
                    AppStrings.ankiImportComplete,
                    style: AppTextStyles.sectionTitle(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: Text(
                    AppStrings.ankiDoneSummary(summary.cardCount),
                    style: AppTextStyles.metricHero(
                      context,
                      color: TurnaTheme.brandTealDark,
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs + 2),
                    child: Text(
                      summary.lessonCount > 0
                          ? AppStrings.ankiLessonsCreated(summary.lessonCount)
                          : AppStrings.anki21bTreeDeferred,
                      style: AppTextStyles.captionSm(context),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
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
                  const SizedBox(height: AppSpacing.md),
                  DoneGroup(
                    title: AppStrings.ankiDoneGroupVocab,
                    rows: [
                      AppStrings.ankiVocabAdded(summary.wordEntryCount),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                DoneGroup(
                  title: AppStrings.ankiDoneGroupSource,
                  rows: [
                    if (summary.newNoteCount > 0)
                      AppStrings.ankiDoneNewNotes(summary.newNoteCount),
                    if (summary.duplicateNoteCount > 0)
                      AppStrings.ankiDoneDuplicateNotes(
                          summary.duplicateNoteCount),
                    if (summary.partCount > 0)
                      AppStrings.ankiDoneParts(summary.partCount)
                    else if (summary.sectionCount > 1)
                      AppStrings.ankiDoneParts(summary.sectionCount),
                    summary.includeMedia
                        ? AppStrings.ankiDoneMediaIncluded
                        : AppStrings.ankiDoneMediaSkipped,
                    AppStrings.ankiDoneReviewRule(),
                  ],
                ),
                // Doc 39 P5: the status-notes block only rendered for the
                // Legacy-parser counters, which official-first never filled —
                // every condition was constant-false and went with the fields.
                const SizedBox(height: AppSpacing.md),
                LearningProgressBadge(kept: keptLearningProgress),
              ],
            ),
          ),
        ),
        SessionActionBand(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SessionPrimaryAction(
                label: AppStrings.ankiStartLearning,
                trailingIcon: Icons.play_arrow_rounded,
                onPressed: onStartLearningNow,
              ),
              const SizedBox(height: AppSpacing.sm),
              // Secondary action: open the memory-card hub (switch /
              // inspect / browse) — a distinct destination from "Done",
              // which simply returns (ADR 0066 §2).
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: onViewDecks,
                  icon: const Icon(Icons.style_outlined, size: 18),
                  label: Text(AppStrings.ankiDoneViewDecks),
                ),
              ),
              const SizedBox(height: AppSpacing.xs + 2),
              TextButton(
                onPressed: onDone,
                child: Text(AppStrings.commonDone),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
