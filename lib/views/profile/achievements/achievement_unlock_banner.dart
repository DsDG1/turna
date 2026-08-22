// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/domain/achievements/achievement_unlock_result.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/achievements/achievement_ui_catalog.dart';
import 'package:turna/views/theme.dart';

/// Inline achievement banner for completion dialogs / pages (plan §7.5).
/// Shows one badge or a collapsed "N 枚徽章" summary; never stacks multiple
/// blocking dialogs for multi-tier unlocks.
class AchievementUnlockBanner extends StatelessWidget {
  final List<AchievementUnlockResult> unlocks;
  final VoidCallback? onViewAll;

  const AchievementUnlockBanner({
    super.key,
    required this.unlocks,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    if (unlocks.isEmpty) return const SizedBox.shrink();
    final accent = TurnaTheme.anatolianClay;
    final first = unlocks.first;
    final firstSeriesTitle = AchievementUiCatalog.titleFor(first.seriesId);
    final cosmetic = AchievementUiCatalog.cosmeticLabel(first.cosmeticRewardId);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  accent.withValues(alpha: 0.9),
                  TurnaTheme.warmSand,
                  accent.withValues(alpha: 0.9),
                ],
              ),
            ),
            child: const Icon(Icons.military_tech_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unlocks.length > 1
                      ? AppStrings.achievementsUnlockBannerCount(unlocks.length)
                      : AppStrings.achievementsUnlockBannerTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  unlocks.length > 1
                      ? '${firstSeriesTitle}${_moreSuffix(context)}'
                      : '$firstSeriesTitle · ${first.target} · '
                            '+${first.gemReward} ${AppStrings.achievementsGemRewardSuffix}'
                            '${cosmetic != null ? ' · $cosmetic' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onViewAll != null)
            TextButton(
              onPressed: onViewAll,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: accent,
              ),
              child: Text(
                AppStrings.achievementsUnlockBannerViewAll,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  String _moreSuffix(BuildContext context) =>
      unlocks.length > 1 ? ' 等 ${unlocks.length} 枚' : '';
}
