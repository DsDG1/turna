// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/gen/assets.gen.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/utils/share_image_generator.dart';
import 'package:turna/views/widgets/turna_geometry.dart';
import 'package:turna/views/widgets/turna_icon.dart';

/// A Bauhaus geometric progress poster designed to be captured and shared.
///
/// Intentionally self-contained (wrapped in [TurnaTheme.lightTheme]) so it
/// renders consistently when captured from an offstage [RepaintBoundary].
class ShareProgressCard extends StatelessWidget {
  final LocalUser user;
  final int streak;
  final int totalXp;
  final int gems;
  final int completedLessons;
  final int perfectLessons;
  final String targetLanguageName;

  const ShareProgressCard({
    super.key,
    required this.user,
    required this.streak,
    required this.totalXp,
    required this.gems,
    required this.completedLessons,
    required this.perfectLessons,
    required this.targetLanguageName,
  });

  @override
  Widget build(BuildContext context) {
    // Keep decode ratio in sync with cappedSharePixelRatio().
    final mascotRatio = cappedSharePixelRatio(
      MediaQuery.devicePixelRatioOf(context),
    );
    return Theme(
      data: TurnaTheme.lightTheme,
      child: Builder(
        builder: (posterCtx) => Container(
          width: 360,
          height: 600,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            gradient: TurnaTheme.brandGradient,
            borderRadius: TurnaTheme.borderRadius,
          ),
          child: Stack(
            children: [
              // Bauhaus geometric background elements
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 6,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: ColoredBox(color: TurnaTheme.anatolianClay),
                      ),
                      Expanded(
                        flex: 3,
                        child: ColoredBox(color: TurnaTheme.warmSand),
                      ),
                      Expanded(
                        flex: 2,
                        child: ColoredBox(color: TurnaTheme.brandReed),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                top: 28,
                right: -24,
                child: TurnaGeometry(
                  kind: TurnaGeometryKind.ripples,
                  accent: TurnaTheme.brandReed,
                  size: 156,
                  intensity: 0.72,
                ),
              ),
              const Positioned(
                bottom: -36,
                left: -28,
                child: TurnaGeometry(
                  kind: TurnaGeometryKind.arch,
                  accent: TurnaTheme.warmSand,
                  size: 168,
                  intensity: 0.45,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xl + AppSpacing.xs,
                  AppSpacing.xl,
                  AppSpacing.xl - 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Poster Masthead
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 4,
                          height: 44,
                          margin: const EdgeInsets.only(top: AppSpacing.xs),
                          decoration: const BoxDecoration(
                            color: TurnaTheme.warmSand,
                            borderRadius: TurnaTheme.borderRadius,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShaderMask(
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        TurnaTheme.sharePosterTitleTop,
                                        TurnaTheme.sharePosterTitleBottom,
                                      ],
                                    ).createShader(bounds),
                                child: Text(
                                  AppStrings.profileShareCardJourneyTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.pageTitle(posterCtx)
                                      .copyWith(
                                        color: TurnaTheme.textOnPrimary,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.0,
                                      ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                AppStrings.profileShareCardJourneySubtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.captionSm(posterCtx)
                                    .copyWith(
                                      color: TurnaTheme.textOnPrimary
                                          .withValues(alpha: 0.82),
                                      letterSpacing: 0.4,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Geometric Stats Panel + Mascot
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topRight,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xl),
                          child: _buildStatsPanel(posterCtx),
                        ),
                        Positioned(
                          top: -12,
                          right: AppSpacing.sm,
                          child: Image.asset(
                            Assets.images.turna.turnaReading.path,
                            height: 76,
                            cacheHeight: (76 * mascotRatio).round(),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Quote block
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: TurnaTheme.brandNavy.withValues(alpha: 0.36),
                        borderRadius: TurnaTheme.borderRadius,
                        border: Border.all(
                          color: TurnaTheme.textOnPrimary.withValues(
                            alpha: 0.16,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Image.asset(
                            Assets.images.turna.turnaWaving.path,
                            height: 64,
                            cacheHeight: (64 * mascotRatio).round(),
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '“${AppStrings.profileShareCardQuote}”',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.cardTitle(
                                    posterCtx,
                                  ).copyWith(color: TurnaTheme.textOnPrimary),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  AppStrings.profileShareCardQuoteSub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption(posterCtx)
                                      .copyWith(
                                        letterSpacing: 0,
                                        color: TurnaTheme.textOnPrimary
                                            .withValues(alpha: 0.78),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Footer stamp
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm + 2,
                        horizontal: AppSpacing.md + 2,
                      ),
                      decoration: BoxDecoration(
                        color: TurnaTheme.textOnPrimary.withValues(alpha: 0.12),
                        borderRadius: TurnaTheme.borderRadius,
                        border: Border(
                          left: const BorderSide(
                            color: TurnaTheme.anatolianClay,
                            width: 4,
                          ),
                          top: BorderSide(
                            color: TurnaTheme.textOnPrimary.withValues(
                              alpha: 0.14,
                            ),
                          ),
                          right: BorderSide(
                            color: TurnaTheme.textOnPrimary.withValues(
                              alpha: 0.14,
                            ),
                          ),
                          bottom: BorderSide(
                            color: TurnaTheme.textOnPrimary.withValues(
                              alpha: 0.14,
                            ),
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            AppStrings.profileShareCardFooterTitle,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.cardTitle(posterCtx).copyWith(
                              color: TurnaTheme.textOnPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppStrings.profileShareCardFooterSub,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.caption(posterCtx).copyWith(
                              letterSpacing: 0,
                              color: TurnaTheme.textOnPrimary.withValues(
                                alpha: 0.82,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsPanel(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md + 2,
      ),
      decoration: BoxDecoration(
        color: TurnaTheme.textOnPrimary.withValues(alpha: 0.13),
        borderRadius: TurnaTheme.borderRadius,
        border: Border.all(
          color: TurnaTheme.textOnPrimary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Language badge row (leaves top-right space for mascot)
          Padding(
            padding: const EdgeInsets.only(right: 76),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  targetLanguageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.sectionTitle(context).copyWith(
                    color: TurnaTheme.textOnPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppStrings.profileShareCardLearnerTag,
                  style: AppTextStyles.caption(context)
                      .copyWith(color: TurnaTheme.warmSand),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Hero XP block
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: TurnaTheme.brandNavy.withValues(alpha: 0.34),
              borderRadius: TurnaTheme.borderRadius,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  totalXp.toString(),
                  style:
                      AppTextStyles.metricHero(
                        context,
                        color: TurnaTheme.textOnPrimary,
                      ).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
                const SizedBox(width: AppSpacing.xs + 2),
                Text(
                  'XP',
                  style: AppTextStyles.caption(context).copyWith(
                    color: TurnaTheme.sharePosterStreak,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                const TurnaIcon(
                  TurnaIconId.bolt,
                  color: TurnaTheme.sharePosterStreak,
                  size: 16,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  AppStrings.profileShareCardTotalXp,
                  style: AppTextStyles.captionSm(context).copyWith(
                    color: TurnaTheme.textOnPrimary.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // 3-column geometric stat blocks
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  icon: TurnaIconId.flame,
                  iconColor: TurnaTheme.sharePosterFlame,
                  value: streak.toString(),
                  label: AppStrings.profileShareCardDayStreak,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatBox(
                  icon: TurnaIconId.diamond,
                  iconColor: TurnaTheme.sharePosterXp,
                  value: gems.toString(),
                  label: AppStrings.profileShareCardGems,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatBox(
                  icon: TurnaIconId.checkCircle,
                  iconColor: TurnaTheme.sharePosterMastered,
                  value: completedLessons.toString(),
                  label: AppStrings.profileShareCardLessons,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final TurnaIconId icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatBox({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm + 2,
        horizontal: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: TurnaTheme.textOnPrimary.withValues(alpha: 0.12),
        borderRadius: TurnaTheme.borderRadius,
        border: Border.all(
          color: TurnaTheme.textOnPrimary.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        children: [
          TurnaIcon(icon, color: iconColor, size: 18),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: AppTextStyles.sectionTitle(context).copyWith(
              color: TurnaTheme.textOnPrimary,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption(context).copyWith(
              letterSpacing: 0,
              color: TurnaTheme.textOnPrimary.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}
