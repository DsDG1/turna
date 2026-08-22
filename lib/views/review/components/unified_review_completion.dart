import 'package:flutter/material.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/achievements/achievement_feedback_banner.dart';
import 'package:turna/views/theme.dart';

/// Unified review completion summary screen.
class UnifiedReviewCompletion extends StatelessWidget {
  final int totalCount;
  final int rememberedCount;
  final int forgottenCount;
  final Duration elapsed;
  final int xpEarned;
  final int gemsEarned;
  final VoidCallback onFinish;

  const UnifiedReviewCompletion({
    super.key,
    required this.totalCount,
    required this.rememberedCount,
    required this.forgottenCount,
    required this.elapsed,
    this.xpEarned = 15,
    this.gemsEarned = 5,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final recallRate = totalCount > 0
        ? ((rememberedCount / totalCount) * 100).round()
        : 100;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 48,
                color: TurnaTheme.brandTeal,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              AppStrings.reviewCompletionTitle,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '你已完成本次复习全部内容',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: TurnaTheme.cardBg(context),
                borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
                border: Border.all(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatColumn(
                    label: '复习总数',
                    value: '$totalCount',
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
                  _StatColumn(
                    label: '记忆率',
                    value: '$recallRate%',
                    color: TurnaTheme.brandTeal,
                  ),
                  _StatColumn(
                    label: '记得 / 不记得',
                    value: '$rememberedCount / $forgottenCount',
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RewardBadge(
                  icon: Icons.bolt_rounded,
                  label: AppStrings.reviewXpEarned(xpEarned),
                  color: TurnaTheme.warning,
                ),
                const SizedBox(width: 12),
                _RewardBadge(
                  icon: Icons.diamond_rounded,
                  label: AppStrings.reviewGemsEarned(gemsEarned),
                  color: TurnaTheme.brandSky,
                ),
              ],
            ),
            // Achievement unlocks from this review session surface here,
            // in the same completion surface as the XP / gem rewards.
            const AchievementFeedbackBanner(),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onFinish,
                // styleFrom treats elevation as a base level (pressed: +6); pin all states flat.
                style: ElevatedButton.styleFrom(
                  backgroundColor: TurnaTheme.brandTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ).copyWith(elevation: const WidgetStatePropertyAll<double>(0)),
                child: Text(
                  AppStrings.commonDone,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: TurnaTheme.textHintColor(context),
          ),
        ),
      ],
    );
  }
}

class _RewardBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _RewardBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
