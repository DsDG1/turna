import 'package:flutter/material.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Shared wizard widgets (maintainability plan §10.5): pure view
/// primitives receiving models + callbacks — no database, engine, DAO or
/// GetIt imports live here.

/// Top-of-page step indicator for the 5-step import wizard.
class WizardStepper extends StatelessWidget {
  final int currentStep; // 0..4
  const WizardStepper({super.key, required this.currentStep});

  // Non-const: AppStrings getters aren't const-evaluable, so the list of step
  // labels has to be built at runtime.
  static final _steps = <(String, IconData)>[
    (AppStrings.ankiStepSelect, Icons.upload_file_rounded),
    (AppStrings.ankiStepParse, Icons.manage_search_rounded),
    (AppStrings.ankiStepPreview, Icons.preview_rounded),
    (AppStrings.ankiStepImport, Icons.cloud_download_rounded),
    (AppStrings.ankiStepDone, Icons.check_circle_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            StepDot(
              label: _steps[i].$1,
              icon: _steps[i].$2,
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
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: i < currentStep
                      ? TurnaTheme.brandTeal.withValues(alpha: 0.5)
                      : TurnaTheme.textHintColor(context)
                          .withValues(alpha: 0.2),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Visual state of one stepper dot.
enum StepState { done, active, idle }

// Public only to satisfy the analyzer's public-API rule; treat as private.
class StepDot extends StatelessWidget {
  final String label;
  final IconData icon;
  final StepState state;
  const StepDot({
    super.key,
    required this.label,
    required this.icon,
    required this.state,
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
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive || isDone
                ? color.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border.all(color: color, width: 1.5),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: isDone
              ? Icon(Icons.check_rounded, size: 16, color: color)
              : Icon(icon, size: 16, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            color: color,
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
  final IconData icon;
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
      color: TurnaTheme.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        side: BorderSide(
          color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
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
                    borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
                  ),
                  child: Icon(icon, color: TurnaTheme.brandTeal, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: TextStyle(
                          fontSize: 12,
                          color: TurnaTheme.textSecondaryColor(context),
                          height: 1.3,
                        ),
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
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: TurnaTheme.textHintColor(context),
        letterSpacing: 0.3,
      ),
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
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: TurnaTheme.brandTeal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: TurnaTheme.textSecondaryColor(context),
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

/// Bottom-anchored primary action bar on the preview step.
class StickyImportBar extends StatelessWidget {
  final VoidCallback? onPressed;
  final String? disabledHint;
  const StickyImportBar({super.key, required this.onPressed, this.disabledHint});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        border: Border(
          top: BorderSide(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (disabledHint != null) ...[
                Text(
                  disabledHint!,
                  style: const TextStyle(
                    color: TurnaTheme.error,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.cloud_download_rounded, size: 20),
                  label: Text(
                    AppStrings.ankiPreviewStartImport,
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
              ),
            ],
          ),
        ),
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
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(
          color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: TurnaTheme.textHintColor(context),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                row,
                style: TextStyle(
                  fontSize: 13,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Single-line learning-progress summary on the done step.
class LearningProgressBadge extends StatelessWidget {
  final bool kept;
  final bool hasScheduling;
  final bool hasReviewHistory;
  const LearningProgressBadge({
    super.key,
    required this.kept,
    required this.hasScheduling,
    required this.hasReviewHistory,
  });

  @override
  Widget build(BuildContext context) {
    if (!kept) {
      return Badge(
        icon: Icons.restart_alt_rounded,
        color: TurnaTheme.textSecondaryColor(context),
        text: AppStrings.ankiDoneProgressReset,
      );
    }
    if (!hasScheduling && !hasReviewHistory) {
      return Badge(
        icon: Icons.check_circle_outline,
        color: TurnaTheme.textHintColor(context),
        text: '已导入',
      );
    }
    return Row(
      children: [
        Expanded(
          child: Badge(
            icon: Icons.check_circle_outline,
            color: TurnaTheme.brandTeal,
            text: AppStrings.ankiDoneProgressKept,
          ),
        ),
      ],
    );
  }
}

class Badge extends StatelessWidget {
  final IconData icon;
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
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
              style: TextStyle(
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
