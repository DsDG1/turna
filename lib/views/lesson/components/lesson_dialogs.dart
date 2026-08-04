// Dart imports:
import 'dart:async';
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/home/components/stat_app_bar.dart';
import 'package:turna/views/theme.dart';

enum MasteryDialogResult { retry, back }

class LessonCelebrationStyle {
  final IconData icon;
  final Color accent;
  final int styleIndex;

  const LessonCelebrationStyle({
    required this.icon,
    required this.accent,
    required this.styleIndex,
  });
}

const lessonCelebrationStyles = [
  LessonCelebrationStyle(
    icon: Icons.celebration_rounded,
    accent: TurnaTheme.brandReed,
    styleIndex: 0,
  ),
  LessonCelebrationStyle(
    icon: Icons.flash_on_rounded,
    accent: TurnaTheme.warning,
    styleIndex: 1,
  ),
  LessonCelebrationStyle(
    icon: Icons.auto_awesome_rounded,
    accent: TurnaTheme.leagueAmethyst,
    styleIndex: 2,
  ),
];

/// Shows the lesson-complete celebration dialog with a gamified summary.
/// Returns when dismissed.
Future<void> showLessonCompletionDialog({
  required BuildContext context,
  required bool Function() isMounted,
  required int correctCount,
  required int incorrectCount,
  required int totalCount,
  required int durationSeconds,
  required int xpEarned,
  required int gemsEarned,
  required bool wasPerfect,
  required List<QuestionResult> questionResults,
  required Random random,
}) async {
  if (!isMounted()) return;

  final navigator = Navigator.of(context);

  await Future.delayed(const Duration(milliseconds: 300));
  if (!isMounted()) return;

  await showDialog<bool>(
    // ignore: use_build_context_synchronously
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _LessonCompletionSummary(
      correctCount: correctCount,
      incorrectCount: incorrectCount,
      totalCount: totalCount,
      durationSeconds: durationSeconds,
      xpEarned: xpEarned,
      gemsEarned: gemsEarned,
      wasPerfect: wasPerfect,
      questionResults: questionResults,
      random: random,
    ),
  );

  if (isMounted()) {
    unawaited(navigator.maybePop());
  }
}

class _LessonCompletionSummary extends StatelessWidget {
  final int correctCount;
  final int incorrectCount;
  final int totalCount;
  final int durationSeconds;
  final int xpEarned;
  final int gemsEarned;
  final bool wasPerfect;
  final List<QuestionResult> questionResults;
  final Random random;

  const _LessonCompletionSummary({
    required this.correctCount,
    required this.incorrectCount,
    required this.totalCount,
    required this.durationSeconds,
    required this.xpEarned,
    required this.gemsEarned,
    required this.wasPerfect,
    required this.questionResults,
    required this.random,
  });

  @override
  Widget build(BuildContext context) {
    final style =
        lessonCelebrationStyles[random.nextInt(lessonCelebrationStyles.length)];
    final accuracy =
        totalCount == 0 ? 0.0 : (correctCount / totalCount).toDouble();
    final accuracyPercent = (accuracy * 100).round();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusXLarge),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(context, style, wasPerfect),
                      const SizedBox(height: 16),
                      _AccuracyRing(
                        accuracy: accuracy,
                        percent: accuracyPercent,
                      ),
                      const SizedBox(height: 16),
                      _buildStatsGrid(context),
                      if (questionResults.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildResultsHeader(context),
                        const SizedBox(height: 8),
                        _QuestionResultList(results: questionResults),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    LessonCelebrationStyle style,
    bool perfect,
  ) {
    final theme = Theme.of(context);
    final l10n = AppStrings;
    final title = switch (style.styleIndex) {
      0 => AppStrings.lessonCompleteTitle1,
      1 => AppStrings.lessonCompleteTitle2,
      2 => AppStrings.lessonCompleteTitle3,
      _ => AppStrings.lessonCompleteTitle1,
    };
    final subtitle = switch (style.styleIndex) {
      0 => AppStrings.lessonCompleteSubtitle1,
      1 => AppStrings.lessonCompleteSubtitle2,
      2 => AppStrings.lessonCompleteSubtitle3,
      _ => AppStrings.lessonCompleteSubtitle1,
    };

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: style.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(style.icon, color: style.accent, size: 40),
            ),
            if (perfect)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: TurnaTheme.success,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: TurnaTheme.textOnPrimary,
                  size: 16,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          perfect ? AppStrings.lessonPerfectLesson : subtitle,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStatsGrid(BuildContext context) {
    return GridView.count(
      primary: false,
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.0,
      children: [
        _StatChip(
          icon: Icons.check_circle_rounded,
          iconColor: TurnaTheme.success,
          label: AppStrings.lessonCorrect,
          value: correctCount,
        ),
        _StatChip(
          icon: Icons.cancel_rounded,
          iconColor: TurnaTheme.error,
          label: AppStrings.lessonWrong,
          value: incorrectCount,
        ),
        _StatChip(
          icon: Icons.timer_rounded,
          iconColor: TurnaTheme.brandSky,
          label: AppStrings.lessonTime,
          valueText: _formatDuration(context, durationSeconds),
        ),
        _StatChip(
          icon: Icons.stars_rounded,
          iconColor: TurnaTheme.warning,
          label: AppStrings.lessonXp,
          value: xpEarned,
        ),
      ],
    );
  }

  Widget _buildResultsHeader(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.fact_check_rounded,
          color: TurnaTheme.brandTeal,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          AppStrings.lessonAnswerBreakdown,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const Spacer(),
        Text(
          AppStrings.lessonResultsCount(correctCount, totalCount),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TurnaTheme.textHint,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: TurnaTheme.primaryCtaDecoration(
                borderRadius:
                    BorderRadius.circular(TurnaTheme.radiusMedium),
                elevated: false,
              ),
              child: InkWell(
                onTap: () => Navigator.of(context).pop(true),
                borderRadius:
                    BorderRadius.circular(TurnaTheme.radiusMedium),
                child: Center(
                  child: Text(
                    AppStrings.lessonContinueUpper,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: TurnaTheme.textOnPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            AppStrings.lessonBackToCourses,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: TurnaTheme.textHint,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(BuildContext context, int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    final l10n = AppStrings;
    if (m == 0) return AppStrings.lessonDurationSeconds(s);
    return AppStrings.lessonDurationMinutes(m, s);
  }
}

class _AccuracyRing extends StatelessWidget {
  final double accuracy;
  final int percent;

  const _AccuracyRing({required this.accuracy, required this.percent});

  @override
  Widget build(BuildContext context) {
    final ringColor = accuracy >= 0.8
        ? TurnaTheme.success
        : accuracy >= 0.5
            ? TurnaTheme.warning
            : TurnaTheme.error;

    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: accuracy.clamp(0.0, 1.0),
            strokeWidth: 10,
            backgroundColor: TurnaTheme.divider,
            valueColor: AlwaysStoppedAnimation<Color>(ringColor),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.lessonPercentValue(percent),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ringColor,
                      ),
                ),
                Text(
                  AppStrings.lessonAccuracy,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TurnaTheme.textHint,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final int? value;
  final String? valueText;

  const _StatChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.value,
    this.valueText,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (valueText != null)
                  Text(
                    valueText!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  AnimatedCounter(
                    target: displayValue,
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TurnaTheme.textHintColor(context),
                        fontWeight: FontWeight.w500,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionResultList extends StatelessWidget {
  final List<QuestionResult> results;

  const _QuestionResultList({required this.results});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final result = results[index];
        return _QuestionResultTile(result: result, index: index + 1);
      },
    );
  }
}

class _QuestionResultTile extends StatelessWidget {
  final QuestionResult result;
  final int index;

  const _QuestionResultTile({required this.result, required this.index});

  @override
  Widget build(BuildContext context) {
    final icon =
        result.correct ? Icons.check_circle_rounded : Icons.cancel_rounded;
    final color = result.correct ? TurnaTheme.success : TurnaTheme.error;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.lessonQuestionResult(index, result.prompt),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!result.correct && result.correctAnswer?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      AppStrings.lessonQuestionAnswer(result.correctAnswer!),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textHint,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the mastery retry dialog. Caller handles the result.
Future<MasteryDialogResult?> showMasteryRetryDialog({
  required BuildContext context,
  required bool Function() isMounted,
  required LessonViewModel vm,
}) async {
  if (!isMounted()) return null;

  final theme = Theme.of(context);

  await Future.delayed(const Duration(milliseconds: 300));
  if (!isMounted()) return null;

  final total = vm.totalInteractionCount;
  final correct = vm.correctAnswers;
  final accuracyPercent = total == 0 ? 0 : ((correct / total) * 100).round();

  return showDialog<MasteryDialogResult>(
    // ignore: use_build_context_synchronously
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusXLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TurnaTheme.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: TurnaTheme.error,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppStrings.lessonNotYet,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.lessonMasteryMessage(correct, total, accuracyPercent),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(MasteryDialogResult.retry),
                child: Text(
                  AppStrings.lessonTryAgain,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(MasteryDialogResult.back),
              child: Text(
                AppStrings.lessonBackToCourses,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: TurnaTheme.textHint,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
