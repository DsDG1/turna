import 'package:flutter/material.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_icon.dart';

/// Shared wizard widgets (maintainability plan §10.5): pure view
/// primitives receiving models + callbacks — no database, engine, DAO or
/// GetIt imports live here.

/// Top-of-page step workspace header for the 5-step import wizard.
class WizardStepper extends StatelessWidget {
  final int currentStep; // 0..4
  const WizardStepper({super.key, required this.currentStep});

  // Non-const: AppStrings getters aren't const-evaluable, so the list of step
  // labels has to be built at runtime.
  static final _steps = <(String, TurnaIconId)>[
    (AppStrings.ankiStepSelect, TurnaIconId.upload),
    (AppStrings.ankiStepParse, TurnaIconId.search),
    (AppStrings.ankiStepPreview, TurnaIconId.eye),
    (AppStrings.ankiStepImport, TurnaIconId.download),
    (AppStrings.ankiStepDone, TurnaIconId.checkCircle),
  ];

  @override
  Widget build(BuildContext context) {
    final safeIndex = currentStep.clamp(0, _steps.length - 1);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        AppSpacing.md,
        AppSpacing.pageMargin,
        AppSpacing.xs,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: TurnaTheme.flatPaperDecoration(
        context,
        borderRadius: TurnaTheme.borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.10),
                  borderRadius: TurnaTheme.borderRadius,
                ),
                child: Text(
                  AppStrings.ankiWizardStepCompact(
                    safeIndex + 1,
                    _steps.length,
                  ),
                  style: AppTextStyles.caption(context).copyWith(
                    color: TurnaTheme.brandTeal,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _steps[safeIndex].$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.captionSm(context).copyWith(
                    color: TurnaTheme.textPrimaryColor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (var i = 0; i < _steps.length; i++) ...[
                StepDot(
                  label: _steps[i].$1,
                  icon: _steps[i].$2,
                  stepNumber: i + 1,
                  stepCount: _steps.length,
                  state: i < currentStep
                      ? StepState.done
                      : i == currentStep
                      ? StepState.active
                      : StepState.idle,
                ),
                if (i < _steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: i < currentStep
                            ? TurnaTheme.brandTeal
                            : TurnaTheme.dividerBg(context),
                        borderRadius: TurnaTheme.borderRadius,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Visual state of one stepper block.
enum StepState { done, active, idle }

// Public only to satisfy the analyzer's public-API rule; treat as private.
class StepDot extends StatelessWidget {
  final String label;
  final TurnaIconId icon;
  final StepState state;
  final int stepNumber;
  final int stepCount;
  const StepDot({
    super.key,
    required this.label,
    required this.icon,
    required this.state,
    this.stepNumber = 1,
    this.stepCount = 5,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      StepState.done => TurnaTheme.brandTeal,
      StepState.active => TurnaTheme.brandTeal,
      StepState.idle => TurnaTheme.textHintColor(context),
    };
    final isActive = state == StepState.active;
    final isDone = state == StepState.done;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: isDone
                ? TurnaTheme.brandTeal
                : isActive
                ? color.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border.all(
              color: isActive || isDone ? color : TurnaTheme.dividerBg(context),
              width: isActive ? 1.5 : 1,
            ),
            borderRadius: TurnaTheme.borderRadius,
          ),
          alignment: Alignment.center,
          child: isDone
              ? const TurnaIcon(
                  TurnaIconId.check,
                  size: 15,
                  color: TurnaTheme.textOnPrimary,
                )
              : TurnaIcon(icon, size: 15, color: color),
        ),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            MediaQuery.textScalerOf(context).scale(1) > 1.3
                ? AppStrings.ankiWizardStepCompact(stepNumber, stepCount)
                : label,
            style: AppTextStyles.caption(context).copyWith(
              letterSpacing: 0,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Section card with an icon, title, and supporting hint. Replaces the
/// stack of equal-weight info cards on the preview screen so the user
/// sees three clear groups (content / mapping / strategy) instead of a
/// flat list of seven.
class SectionCard extends StatelessWidget {
  final TurnaIconId icon;
  final String title;
  final String hint;
  final List<Widget> children;

  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      // ADR 0062：导入向导的分组卡 → 中性淡彩实面 + 同色描边。
      color: TurnaTheme.glassSolid(
        context,
        TurnaTheme.glassNeutral,
        level: GlassLevel.l1Subtle,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: TurnaTheme.borderRadius,
        side: BorderSide(
          color: TurnaTheme.glassStroke(
            context,
            TurnaTheme.glassNeutral,
            level: GlassLevel.l1Subtle,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                    borderRadius: TurnaTheme.borderRadius,
                  ),
                  child: TurnaIcon(icon, color: TurnaTheme.brandTeal, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.cardTitle(context)),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: AppTextStyles.captionSm(context)
                            .copyWith(height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small uppercase-ish label used as an in-card subheader (e.g. "牌组结构").
class Subheader extends StatelessWidget {
  final String text;
  const Subheader({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.caption(context)
          .copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.3),
    );
  }
}

/// 4-up compact stat row for the content section.
class StatStrip extends StatelessWidget {
  final List<(String, int)> items;
  const StatStrip({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: StatChip(label: items[i].$1, value: items[i].$2),
          ),
          if (i < items.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class StatChip extends StatelessWidget {
  final String label;
  final int value;
  const StatChip({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: TurnaTheme.brandTeal.withValues(alpha: 0.05),
        borderRadius: TurnaTheme.borderRadius,
        border: Border.all(color: TurnaTheme.brandTeal.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: AppTextStyles.sectionTitle(context).copyWith(
              fontWeight: FontWeight.w800,
              color: TurnaTheme.brandTeal,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.caption(context).copyWith(
              color: TurnaTheme.textSecondaryColor(context),
              letterSpacing: 0,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Bottom-anchored primary action bar on the preview step —「湿地雾光」
/// 步骤流程的底部固定阶段操作（[SessionActionBand] + [SessionPrimaryAction]
/// 换壳，行为与禁用提示原样）。
class StickyImportBar extends StatelessWidget {
  final VoidCallback? onPressed;
  final String? disabledHint;
  const StickyImportBar({
    super.key,
    required this.onPressed,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    return SessionActionBand(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (disabledHint != null) ...[
            Text(
              disabledHint!,
              style: AppTextStyles.captionSm(context)
                  .copyWith(color: TurnaTheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
          ],
          SessionPrimaryAction(
            label: AppStrings.ankiPreviewStartImport,
            trailingIcon: TurnaIconId.download,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

/// Grouped detail block on the done step.
class DoneGroup extends StatelessWidget {
  final String title;
  final List<String> rows;
  const DoneGroup({super.key, required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: TurnaTheme.glassDecoration(
        context,
        TurnaTheme.glassNeutral,
        level: GlassLevel.l1Subtle,
        borderRadius: TurnaTheme.borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.caption(context)
                .copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.3),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(row, style: AppTextStyles.captionSm(context)),
            ),
        ],
      ),
    );
  }
}

/// Single-line learning-progress summary on the done step.
class LearningProgressBadge extends StatelessWidget {
  final bool kept;
  const LearningProgressBadge({super.key, required this.kept});

  @override
  Widget build(BuildContext context) {
    if (!kept) {
      return Badge(
        icon: TurnaIconId.restart,
        color: TurnaTheme.textSecondaryColor(context),
        text: AppStrings.ankiDoneProgressReset,
      );
    }
    // Doc 39 P5: official-first has no carried-over scheduling/history, so
    // the reset/imported pair is the whole badge now.
    return Badge(
      icon: TurnaIconId.checkCircle,
      color: TurnaTheme.textHintColor(context),
      text: AppStrings.ankiImportedBadge,
    );
  }
}

class Badge extends StatelessWidget {
  final TurnaIconId icon;
  final Color color;
  final String text;
  const Badge({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: TurnaTheme.borderRadius,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TurnaIcon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: AppTextStyles.captionSm(context)
                .copyWith(fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const InfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap both halves in Flexible so the row can shrink and the value
          // ellipsizes instead of overflowing the card on narrow screens.
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.captionSm(context),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: AppTextStyles.captionSm(context).copyWith(
                fontWeight: FontWeight.w600,
                color: TurnaTheme.textPrimaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
