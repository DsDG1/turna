// Dart imports:
import 'dart:async';
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/application/lesson_viewmodel.dart';
import 'package:varnamala/views/home/components/stat_app_bar.dart';
import 'package:varnamala/views/theme.dart';

enum MasteryDialogResult { retry, back }

class LessonCelebrationStyle {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;

  const LessonCelebrationStyle({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
  });
}

const lessonCelebrationStyles = [
  LessonCelebrationStyle(
    icon: Icons.celebration_rounded,
    accent: VarnamalaTheme.peacockTurquoise,
    title: 'Lesson Complete!',
    subtitle: 'Brilliant focus. You cleared this lesson.',
  ),
  LessonCelebrationStyle(
    icon: Icons.flash_on_rounded,
    accent: VarnamalaTheme.warning,
    title: 'That Was Fast!',
    subtitle: 'You are climbing fast. Keep the streak alive.',
  ),
  LessonCelebrationStyle(
    icon: Icons.auto_awesome_rounded,
    accent: VarnamalaTheme.leagueAmethyst,
    title: 'Excellent Work!',
    subtitle: 'Every lesson gets you closer to mastery.',
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
    final style = lessonCelebrationStyles[
        random.nextInt(lessonCelebrationStyles.length)];
    final accuracy =
        totalCount == 0 ? 0.0 : (correctCount / totalCount).toDouble();
    final accuracyPercent = (accuracy * 100).round();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusXLarge),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
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
                  color: VarnamalaTheme.success,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          style.title,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          perfect ? 'Perfect lesson! All answers correct.' : style.subtitle,
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
      childAspectRatio: 2.4,
      children: [
        _StatChip(
          icon: Icons.check_circle_rounded,
          iconColor: VarnamalaTheme.success,
          label: 'Correct',
          value: correctCount,
        ),
        _StatChip(
          icon: Icons.cancel_rounded,
          iconColor: VarnamalaTheme.error,
          label: 'Wrong',
          value: incorrectCount,
        ),
        _StatChip(
          icon: Icons.timer_rounded,
          iconColor: VarnamalaTheme.peacockCyan,
          label: 'Time',
          valueText: _formatDuration(durationSeconds),
        ),
        _StatChip(
          icon: Icons.stars_rounded,
          iconColor: VarnamalaTheme.warning,
          label: 'XP',
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
          color: VarnamalaTheme.peacockTeal,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          'Answer breakdown',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const Spacer(),
        Text(
          '$correctCount / $totalCount',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: VarnamalaTheme.textHint,
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
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Continue',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            'Back to Courses',
            style: theme.textTheme.bodyMedium?.copyWith(
                  color: VarnamalaTheme.textHint,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
    );
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}

class _AccuracyRing extends StatelessWidget {
  final double accuracy;
  final int percent;

  const _AccuracyRing({required this.accuracy, required this.percent});

  @override
  Widget build(BuildContext context) {
    final ringColor = accuracy >= 0.8
        ? VarnamalaTheme.success
        : accuracy >= 0.5
            ? VarnamalaTheme.warning
            : VarnamalaTheme.error;

    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: accuracy.clamp(0.0, 1.0),
            strokeWidth: 10,
            backgroundColor: VarnamalaTheme.divider,
            valueColor: AlwaysStoppedAnimation<Color>(ringColor),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$percent%',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ringColor,
                      ),
                ),
                Text(
                  'accuracy',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: VarnamalaTheme.textHint,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (valueText != null)
                  Text(
                    valueText!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  )
                else
                  AnimatedCounter(
                    target: displayValue,
                    style: Theme.of(context).textTheme.titleMedium!.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: VarnamalaTheme.textHintColor(context),
                        fontWeight: FontWeight.w500,
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
    final icon = result.correct
        ? Icons.check_circle_rounded
        : Icons.cancel_rounded;
    final color = result.correct ? VarnamalaTheme.success : VarnamalaTheme.error;

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
                  '$index. ${result.prompt}',
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
                      'Answer: ${result.correctAnswer}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: VarnamalaTheme.textHint,
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
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusXLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: VarnamalaTheme.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: VarnamalaTheme.error,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Not Yet',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'You got $correct / $total ($accuracyPercent%). You need 80% to pass. Try again!',
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
                child: const Text(
                  'Try Again',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(MasteryDialogResult.back),
              child: Text(
                'Back to Courses',
                style: theme.textTheme.bodyMedium?.copyWith(
                      color: VarnamalaTheme.textHint,
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
