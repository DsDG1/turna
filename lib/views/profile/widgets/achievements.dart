// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/achievements_provider.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/domain/achievement.dart';
import 'package:varnamala/domain/game/user_game_state.dart';
import 'package:varnamala/views/theme.dart';

class Achievements extends StatefulWidget {
  const Achievements({Key? key}) : super(key: key);

  @override
  State<Achievements> createState() => _AchievementsState();
}

class _AchievementsState extends State<Achievements> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    const achievements = AchievementsProvider.allAchievements;
    final gameProvider = Provider.of<GameProvider>(context, listen: false);

    return StreamBuilder(
      stream: gameProvider.getUserGameStateStream(),
      builder: (context, snapshot) {
        final userData = snapshot.data ?? UserGameState.empty;

        final displayedAchievements =
            _expanded ? achievements : achievements.take(3).toList();
        final remainingCount = achievements.length - displayedAchievements.length;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(
                  context, 'Achievements', Icons.military_tech_rounded),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: VarnamalaTheme.cardBg(context),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusLarge),
                  border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
                ),
                child: Column(
                  children: [
                    ...displayedAchievements.map((achievement) {
                      final progress = _getProgress(achievement, userData);
                      final currentLevel = achievement.getCurrentLevel(progress);
                      final nextTarget = achievement.getTargetForLevel(currentLevel);
                      
                      return Column(
                        children: [
                          _AchievementTile(
                            icon: achievement.icon,
                            iconColor: achievement.color,
                            label: achievement.title,
                            description: achievement.description,
                            current: progress,
                            target: nextTarget,
                            level: currentLevel,
                            maxLevel: achievement.maxLevel,
                          ),
                          if (achievement != displayedAchievements.last ||
                              (!_expanded && remainingCount > 0))
                            Divider(
                                height: 1, indent: 16, endIndent: 16, color: VarnamalaTheme.dividerBg(context)),
                        ],
                      );
                    }),
                    if (!_expanded && remainingCount > 0)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _expanded = true;
                            });
                          },
                          borderRadius: const BorderRadius.only(
                            bottomLeft:
                                Radius.circular(VarnamalaTheme.radiusLarge),
                            bottomRight:
                                Radius.circular(VarnamalaTheme.radiusLarge),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Text(
                                  'View $remainingCount more',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: VarnamalaTheme.peacockTeal,
                                      ),
                                ),
                                const Spacer(),
                                const Icon(Icons.chevron_right_rounded,
                                    color: VarnamalaTheme.peacockTeal, size: 22),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if(_expanded)
                       Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _expanded = false;
                            });
                          },
                          borderRadius: const BorderRadius.only(
                            bottomLeft:
                                Radius.circular(VarnamalaTheme.radiusLarge),
                            bottomRight:
                                Radius.circular(VarnamalaTheme.radiusLarge),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Text(
                                  'Show less',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: VarnamalaTheme.peacockTeal,
                                      ),
                                ),
                                const Spacer(),
                                const Icon(Icons.expand_less_rounded,
                                    color: VarnamalaTheme.peacockTeal, size: 22),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  int _getProgress(Achievement achievement, UserGameState data) {
    switch (achievement.type) {
      case AchievementType.scholar:
        return data.wordsLearned;
      case AchievementType.sage:
        return data.score;
      case AchievementType.wildfire:
        return data.streak;
      case AchievementType.champion:
        return data.lessonsCompleted;
      case AchievementType.sharpshooter:
        return data.perfectLessons;
      default:
        return 0;
    }
  }

  Widget _sectionTitle(BuildContext context, String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: VarnamalaTheme.peacockTeal, size: 22),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String description;
  final int current;
  final int target;
  final int level;
  final int maxLevel;

  const _AchievementTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.description,
    required this.current,
    required this.target,
    required this.level,
    required this.maxLevel,
  });

  @override
  Widget build(BuildContext context) {
    // An achievement is complete once it reaches its maximum level, which
    // happens exactly when progress meets or exceeds the final target.
    bool isCompleted = level >= maxLevel;
    int displayTarget = isCompleted ? current : target; 
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius:
                  BorderRadius.circular(VarnamalaTheme.radiusMedium),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor, size: 24),
                if (!isCompleted)
                  Text(
                    'Lv.$level',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: iconColor,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: VarnamalaTheme.textSecondary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                            VarnamalaTheme.radiusRound),
                        child: LinearProgressIndicator(
                          value: displayTarget > 0 ? (current / displayTarget).clamp(0.0, 1.0) : 0,
                          minHeight: 8,
                          backgroundColor: VarnamalaTheme.dividerBg(context),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              VarnamalaTheme.success),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$current/$displayTarget',
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: VarnamalaTheme.textHint,
                                fontWeight: FontWeight.w600,
                              ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
