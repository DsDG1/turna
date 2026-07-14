import 'package:flutter/material.dart';

import 'package:varnamala/core/sm2.dart';
import 'package:varnamala/views/theme.dart';

class ReviewRatingBar extends StatelessWidget {
  final ValueChanged<ReviewGrade> onRate;
  final String prompt;

  const ReviewRatingBar({
    super.key,
    required this.onRate,
    this.prompt = '你认识这个词吗？',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _RateButton(
                label: '不认识',
                color: VarnamalaTheme.error,
                onTap: () => onRate(ReviewGrade.unknown),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RateButton(
                label: '认识',
                color: VarnamalaTheme.success,
                onTap: () => onRate(ReviewGrade.known),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          prompt,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: VarnamalaTheme.textHintColor(context),
              ),
        ),
      ],
    );
  }
}

class _RateButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RateButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
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

  const ReviewEmptyState({
    super.key,
    required this.onRefresh,
    required this.dueCount,
    this.title = 'Review',
    this.emptyMessage = 'You\'ve reviewed everything for now.',
    this.dueMessage = 'words are already due — pull to refresh',
  });

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
              color: VarnamalaTheme.success,
            ),
            const SizedBox(height: 16),
            Text(
              'No items due for review',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              dueCount > 0
                  ? '$dueCount $dueMessage'
                  : emptyMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: VarnamalaTheme.textSecondaryColor(context),
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
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

  const ReviewCompletionState({
    super.key,
    required this.reviewedCount,
    required this.dueCount,
    required this.xpEarned,
    required this.gemsEarned,
    required this.onDone,
    required this.onReviewMore,
    this.title = 'Session Complete!',
    this.completionMessage = 'You reviewed everything.',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 64,
              color: VarnamalaTheme.success,
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
                    color: VarnamalaTheme.textSecondaryColor(context),
                  ),
            ),
            if (xpEarned > 0 || gemsEarned > 0) ...[
              const SizedBox(height: 12),
              Text(
                [
                  if (xpEarned > 0) '+$xpEarned XP',
                  if (gemsEarned > 0) '+$gemsEarned Gems',
                ].join('  \u00B7  '),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: VarnamalaTheme.peacockTeal,
                    ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: onDone,
                  child: const Text('Done'),
                ),
                const SizedBox(width: 12),
                if (dueCount > 0)
                  ElevatedButton.icon(
                    onPressed: onReviewMore,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Review More'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
