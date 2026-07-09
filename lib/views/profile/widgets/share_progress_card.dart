// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:words625/core/enums.dart';
import 'package:words625/core/extensions.dart';
import 'package:words625/domain/auth/local_user.dart';
import 'package:words625/views/theme.dart';

/// A brand-styled progress card designed to be captured and shared.
///
/// This widget is intentionally self-contained (it does not depend on the
/// surrounding theme) so it renders consistently when captured from an
/// offstage [RepaintBoundary].
class ShareProgressCard extends StatelessWidget {
  final SerializableFirebaseUser user;
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
      data: VarnamalaTheme.lightTheme,
      child: Container(
        width: 360,
        height: 480,
        decoration: const BoxDecoration(
          gradient: VarnamalaTheme.peacockGradient,
          borderRadius: BorderRadius.all(
            Radius.circular(VarnamalaTheme.radiusXLarge),
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
                  color: Colors.white.withValues(alpha: 0.08),
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
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App brand
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(
                              VarnamalaTheme.radiusMedium),
                        ),
                        child: const Icon(
                          Icons.school_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Varnamala',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // User greeting
                  Text(
                    '${user.displayName ?? 'Learner'} is learning',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    targetLanguage.name.toTitleCase,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Stats grid
                  Row(
                    children: [
                      Expanded(
                        child: _StatBox(
                          icon: Icons.local_fire_department_rounded,
                          value: streak.toString(),
                          label: 'Day Streak',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatBox(
                          icon: Icons.bolt_rounded,
                          value: totalXp.toString(),
                          label: 'Total XP',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatBox(
                          icon: Icons.diamond_rounded,
                          value: gems.toString(),
                          label: 'Gems',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatBox(
                          icon: Icons.check_circle_rounded,
                          value: completedLessons.toString(),
                          label: 'Lessons',
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Footer
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(VarnamalaTheme.radiusMedium),
                    ),
                    child: const Text(
                      'Join me on Varnamala!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
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
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatBox({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
