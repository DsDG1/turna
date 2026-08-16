// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/enums.dart';
import 'package:turna/core/extensions.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/gen/assets.gen.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// A brand-styled progress poster designed to be captured and shared.
///
/// This widget is intentionally self-contained (it does not depend on the
/// surrounding theme) so it renders consistently when captured from an
/// offstage [RepaintBoundary].
class ShareProgressCard extends StatelessWidget {
  final LocalUser user;
  final int streak;
  final int totalXp;
  final int gems;
  final int completedLessons;
  final int perfectLessons;
  final TargetLanguage targetLanguage;

  const ShareProgressCard({
    super.key,
    required this.user,
    required this.streak,
    required this.totalXp,
    required this.gems,
    required this.completedLessons,
    required this.perfectLessons,
    required this.targetLanguage,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: TurnaTheme.lightTheme,
      child: Container(
        width: 360,
        height: 600,
        decoration: const BoxDecoration(
          gradient: TurnaTheme.brandGradient,
          borderRadius: BorderRadius.all(
            Radius.circular(TurnaTheme.radiusXLarge),
          ),
        ),
        child: Stack(
          children: [
            // Decorative background circles
            Positioned(
              top: -60,
              right: -40,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TurnaTheme.textOnPrimary.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              bottom: -80,
              left: -60,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TurnaTheme.textOnPrimary.withValues(alpha: 0.06),
                ),
              ),
            ),
            // Sparkles
            Positioned(
              top: 90,
              left: 28,
              child: Icon(
                Icons.auto_awesome,
                size: 14,
                color: TurnaTheme.textOnPrimary.withValues(alpha: 0.45),
              ),
            ),
            Positioned(
              top: 64,
              right: 36,
              child: Icon(
                Icons.star_rounded,
                size: 16,
                color: TurnaTheme.textOnPrimary.withValues(alpha: 0.5),
              ),
            ),
            Positioned(
              top: 210,
              right: 24,
              child: Icon(
                Icons.auto_awesome,
                size: 12,
                color: TurnaTheme.textOnPrimary.withValues(alpha: 0.35),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              child: Column(
                children: [
                  // Title (no logo)
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFEAFBF5), Color(0xFF8FE8D3)],
                    ).createShader(bounds),
                    child: Text(
                      AppStrings.profileShareCardJourneyTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppStrings.profileShareCardJourneySubtitle,
                    style: TextStyle(
                      color: TurnaTheme.textOnPrimary.withValues(alpha: 0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Mascot overlapping the stats card
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 42),
                        child: _buildStatsCard(),
                      ),
                      Positioned(
                        top: -4,
                        child: Image.asset(
                          Assets.images.turna.turnaReading.path,
                          height: 88,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Quote with waving mascot
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset(
                        Assets.images.turna.turnaWaving.path,
                        height: 76,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '“${AppStrings.profileShareCardQuote}”',
                              style: const TextStyle(
                                color: TurnaTheme.textOnPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              AppStrings.profileShareCardQuoteSub,
                              style: TextStyle(
                                color: TurnaTheme.textOnPrimary
                                    .withValues(alpha: 0.75),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Footer
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: TurnaTheme.textOnPrimary.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(TurnaTheme.radiusMedium),
                    ),
                    child: Column(
                      children: [
                        Text(
                          AppStrings.profileShareCardFooterTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: TurnaTheme.textOnPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppStrings.profileShareCardFooterSub,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                TurnaTheme.textOnPrimary.withValues(alpha: 0.8),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
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
    );
  }

  Widget _buildStatsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 14),
      decoration: BoxDecoration(
        color: TurnaTheme.textOnPrimary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(
          color: TurnaTheme.textOnPrimary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Language
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      targetLanguage.name.toTitleCase,
                      style: const TextStyle(
                        color: TurnaTheme.textOnPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.profileShareCardLearnerTag,
                      style: TextStyle(
                        color: TurnaTheme.textOnPrimary.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Total XP
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppStrings.profileShareCardTotalXp,
                        style: TextStyle(
                          color:
                              TurnaTheme.textOnPrimary.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.bolt_rounded,
                        color: Color(0xFFFFD54F),
                        size: 16,
                      ),
                    ],
                  ),
                  Text(
                    totalXp.toString(),
                    style: const TextStyle(
                      color: TurnaTheme.textOnPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'XP',
                    style: TextStyle(
                      color: TurnaTheme.textOnPrimary.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: const Color(0xFFFF9D5C),
                  value: streak.toString(),
                  label: AppStrings.profileShareCardDayStreak,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatBox(
                  icon: Icons.diamond_rounded,
                  iconColor: const Color(0xFF8FD8F0),
                  value: gems.toString(),
                  label: AppStrings.profileShareCardGems,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatBox(
                  icon: Icons.check_circle_rounded,
                  iconColor: const Color(0xFF9CE8A8),
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
  final IconData icon;
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
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: TurnaTheme.textOnPrimary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: TurnaTheme.textOnPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: TurnaTheme.textOnPrimary.withValues(alpha: 0.85),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
