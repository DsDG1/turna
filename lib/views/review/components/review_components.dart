import 'package:flutter/material.dart';

import 'package:turna/core/sm2.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/achievements/achievement_feedback_banner.dart';
import 'package:turna/views/theme.dart';

/// Binary rating bar only: 不认识 / 认识.
/// Optional [failPreview] / [passPreview] show FSRS interval chips (ADR 0028).
class ReviewRatingBar extends StatelessWidget {
  final ValueChanged<ReviewGrade> onRate;
  final String prompt;
  final String? failPreview;
  final String? passPreview;

  ReviewRatingBar({
    super.key,
    required this.onRate,
    String? prompt,
    this.failPreview,
    this.passPreview,
  }) : prompt = prompt ?? AppStrings.reviewDoYouKnow;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _RateButton(
                label: AppStrings.reviewDontKnow,
                subtitle: failPreview ?? AppStrings.srsPreviewUnknown,
                color: TurnaTheme.error,
                onTap: () => onRate(ReviewGrade.unknown),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RateButton(
                label: AppStrings.reviewKnowIt,
                subtitle: passPreview,
                color: TurnaTheme.success,
                onTap: () => onRate(ReviewGrade.known),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          prompt,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TurnaTheme.textHintColor(context),
              ),
        ),
      ],
    );
  }
}

class _RateButton extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RateButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ReviewEmptyState extends StatelessWidget {
  final VoidCallback onRefresh;
  final int dueCount;
  final String title;
  final String emptyMessage;
  final String dueMessage;

  ReviewEmptyState({
    super.key,
    required this.onRefresh,
    required this.dueCount,
    String? title,
    String? emptyMessage,
    String? dueMessage,
  })  : title = title ?? AppStrings.reviewEmptyTitle,
        emptyMessage = emptyMessage ?? AppStrings.reviewEmptyMessage,
        dueMessage = dueMessage ?? AppStrings.reviewDueMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 64,
              color: TurnaTheme.success,
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.reviewEmptyTitle,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              dueCount > 0
                  ? AppStrings.reviewDueCountMessage(dueCount, dueMessage)
                  : emptyMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppStrings.commonRefresh),
            ),
          ],
        ),
      ),
    );
  }
}

class ReviewCompletionState extends StatelessWidget {
  final int reviewedCount;
  final int dueCount;
  final int xpEarned;
  final int gemsEarned;
  final VoidCallback onDone;
  final VoidCallback onReviewMore;
  final String title;
  final String completionMessage;

  ReviewCompletionState({
    super.key,
    required this.reviewedCount,
    required this.dueCount,
    required this.xpEarned,
    required this.gemsEarned,
    required this.onDone,
    required this.onReviewMore,
    String? title,
    String? completionMessage,
  })  : title = title ?? AppStrings.reviewCompletionTitle,
        completionMessage =
            completionMessage ?? AppStrings.reviewCompletionMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.reviewReviewAppBarTitle)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 64,
              color: TurnaTheme.success,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              completionMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
            if (xpEarned > 0 || gemsEarned > 0) ...[
              const SizedBox(height: 12),
              Text(
                [
                  if (xpEarned > 0) AppStrings.reviewXpEarned(xpEarned),
                  if (gemsEarned > 0) AppStrings.reviewGemsEarned(gemsEarned),
                ].join('  ·  '),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: TurnaTheme.brandTeal,
                    ),
              ),
            ],
            const AchievementFeedbackBanner(),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: onDone,
                  child: Text(AppStrings.commonDone),
                ),
                const SizedBox(width: 12),
                if (dueCount > 0)
                  ElevatedButton.icon(
                    onPressed: onReviewMore,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(AppStrings.commonRefresh),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
