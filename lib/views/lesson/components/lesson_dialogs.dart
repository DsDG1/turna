// Dart imports:
import 'dart:async';
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/application/lesson_viewmodel.dart';
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

/// Shows the lesson-complete celebration dialog. Returns when dismissed.
Future<void> showLessonCompletionDialog({
  required BuildContext context,
  required bool Function() isMounted,
  required Random random,
}) async {
  if (!isMounted()) return;

  final navigator = Navigator.of(context);
  final theme = Theme.of(context);

  await Future.delayed(const Duration(milliseconds: 300));
  if (!isMounted()) return;

  final style =
      lessonCelebrationStyles[random.nextInt(lessonCelebrationStyles.length)];

  await showDialog<bool>(
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
                color: style.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(style.icon, color: style.accent, size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              style.title,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              style.subtitle,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
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

  if (isMounted()) {
    unawaited(navigator.maybePop());
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
