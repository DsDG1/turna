// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/ai/textbook/import_plan.dart';
import 'package:turna/application/ai/textbook/textbook_import_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Conflict preview: resource collision summary + per-section import actions.
class TextbookConflictPreview extends StatelessWidget {
  final TextbookImportProvider provider;

  const TextbookConflictPreview({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final report = provider.collisionReport;
    final plans = provider.sectionPlans;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.aiTextbookConflictTitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          AppStrings.aiTextbookConflictSubtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TurnaTheme.textHintColor(context),
              ),
        ),
        const SizedBox(height: 12),
        if (report != null)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryChip(
                label: AppStrings.aiTextbookCollisionNew(report.totalNew),
                color: TurnaTheme.brandTeal,
              ),
              _SummaryChip(
                label:
                    AppStrings.aiTextbookCollisionDup(report.totalDuplicates),
                color: TurnaTheme.warning,
              ),
              _SummaryChip(
                label: AppStrings.aiTextbookWords(report.newWords),
                color: TurnaTheme.brandSky,
              ),
              _SummaryChip(
                label: AppStrings.aiTextbookExpressions(report.newExpressions),
                color: TurnaTheme.leagueAmethyst,
              ),
            ],
          ),
        const SizedBox(height: 12),
        Expanded(
          child: plans.isEmpty
              ? Center(
                  child: Text(
                    AppStrings.aiTextbookReviewEmpty,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: TurnaTheme.textHintColor(context),
                        ),
                  ),
                )
              : ListView.separated(
                  itemCount: plans.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final plan = plans[i];
                    return _PlanCard(plan: plan);
                  },
                ),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final Color color;

  const _SummaryChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final SectionImportPlan plan;

  const _PlanCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final actionLabel = _actionLabel(plan.action);
    final actionColor = _actionColor(plan.action);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.chapterTitle.isEmpty ? plan.sourceId : plan.chapterTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
                ),
                child: Text(
                  actionLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: actionColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            plan.targetId != plan.sourceId &&
                    plan.action == ImportAction.appendNew
                ? '${plan.sourceId} → ${plan.targetId}'
                : plan.sourceId,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                  fontFamily: 'monospace',
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '${AppStrings.aiTextbookWords(plan.wordCount)} · '
            '${AppStrings.aiTextbookExpressions(plan.expressionCount)} · '
            '${AppStrings.aiTextbookGrammar(plan.grammarCount)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _actionLabel(ImportAction a) => switch (a) {
        ImportAction.append => AppStrings.aiTextbookActionAppend,
        ImportAction.merge => AppStrings.aiTextbookActionMerge,
        ImportAction.skip => AppStrings.aiTextbookActionSkip,
        ImportAction.replace => AppStrings.aiTextbookActionReplace,
        ImportAction.appendNew => AppStrings.aiTextbookActionAppendNew,
      };

  Color _actionColor(ImportAction a) => switch (a) {
        ImportAction.append => TurnaTheme.brandTeal,
        ImportAction.merge => TurnaTheme.brandSky,
        ImportAction.skip => TurnaTheme.textHint,
        ImportAction.replace => TurnaTheme.warning,
        ImportAction.appendNew => TurnaTheme.leagueAmethyst,
      };
}
