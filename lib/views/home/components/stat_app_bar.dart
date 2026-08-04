// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/game_provider.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/gems_display.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/loader.dart';

class StatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const StatAppBar({Key? key}) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 60,
      leading: const Padding(
        padding: EdgeInsets.only(left: 8),
        child: LanguageSwitch(),
      ),
      leadingWidth: 64,
      title: const SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScoreCard(),
            Padding(padding: EdgeInsets.symmetric(horizontal: 4)),
            Streak(),
            Padding(padding: EdgeInsets.symmetric(horizontal: 4)),
            GemsDisplay(),
          ],
        ),
      ),
      actions: const [],
    );
  }
}

/// Globe button in the Learn-tab app bar. Opens the course-management page
/// (switch / reorder / add / delete courses) — it used to be an inline
/// popup menu, now all of that lives in [CourseManagementPage].
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: AppStrings.courseManagementTitle,
      icon: const Icon(
        Icons.language_rounded,
        size: 22,
        color: TurnaTheme.brandTeal,
      ),
      onPressed: () => context.router.push(const CourseManagementRoute()),
    );
  }
}

class Streak extends StatelessWidget {
  const Streak({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: TurnaTheme.streakChipBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded,
              color: TurnaTheme.streakChipText(context), size: 20),
          const SizedBox(width: 4),
          StreamBuilder<int>(
            stream: context.read<GameProvider>().getUserStreakStream(),
            builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Loader();
              }
              if (snapshot.hasError) {
                return const Text('0');
              }
              return AnimatedCounter(
                target: snapshot.data ?? 0,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: TurnaTheme.streakChipText(context),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ScoreCard extends StatelessWidget {
  const ScoreCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: TurnaTheme.scoreChipBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.stars_rounded,
              color: TurnaTheme.scoreChipText(context), size: 20),
          const SizedBox(width: 4),
          StreamBuilder<int>(
            stream: context.read<GameProvider>().getUserScoreStream(),
            builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Loader();
              }
              if (snapshot.hasError) {
                return const Text('0');
              }
              return AnimatedCounter(
                target: snapshot.data ?? 0,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: TurnaTheme.scoreChipText(context),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class AnimatedCounter extends StatefulWidget {
  final int target;
  final TextStyle style;

  const AnimatedCounter({
    Key? key,
    required this.target,
    required this.style,
  }) : super(key: key);

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter> {
  /// The value the counter was last displaying. The next tween animates from
  /// this value to the new target, so score/streak updates count up from the
  /// previous number instead of resetting to zero on every stream emit.
  late int _from = widget.target;

  @override
  void didUpdateWidget(covariant AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _from = oldWidget.target;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: TweenAnimationBuilder<int>(
        tween: IntTween(begin: _from, end: widget.target),
        duration: const Duration(milliseconds: 1000),
        builder: (context, value, child) {
          return Text(
            value.toString(),
            style: widget.style,
          );
        },
      ),
    );
  }
}
