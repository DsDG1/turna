// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/play/play_review_eligibility.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/service/tab_router.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/gems_display.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/loader.dart';

class StatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const StatAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 60,
      leading: const CourseSwitchButton(),
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
            Padding(padding: EdgeInsets.symmetric(horizontal: 4)),
            DueChip(),
          ],
        ),
      ),
      actions: const [],
    );
  }
}

/// Course switcher entry in the Learn-tab app bar: a bare globe icon that
/// opens the course-management page, where switch / reorder / add / delete
/// live. Icon-only by design (change 2); the tooltip keeps it labeled for
/// screen readers.
class CourseSwitchButton extends StatelessWidget {
  const CourseSwitchButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: AppStrings.courseManagementTitle,
      onPressed: () => context.router.push(CourseManagementRoute()),
      icon: const Icon(
        Icons.language_rounded,
        size: 22,
        color: TurnaTheme.brandTeal,
      ),
    );
  }
}

class DueChip extends StatelessWidget {
  const DueChip({super.key});

  @override
  Widget build(BuildContext context) {
    final srsDue = context.select((SrsProvider p) => p.dueCount);
    final exprDue = context.select((SrsProvider p) => p.expressionDueCount);
    final grammarDue = context.select((GrammarReviewProvider p) => p.dueCount);
    final mistakes = context.select((MistakeProvider p) => p.count);
    final scope = context.select((CourseProvider p) => p.courseScope);
    final ankiWords = context.select((SrsProvider p) => p.getDueAnkiWords());
    return ListenableBuilder(
      listenable: OfficialFormalDueRepository.instance,
      builder: (context, _) {
        final dueRepo = OfficialFormalDueRepository.instance;
        final due = PlayReviewEligibility.isAnkiScope(scope)
            ? (dueRepo.snapshot.unavailable
                ? 0
                : dueRepo.aggregatedAnkiDue(ankiWords))
            : srsDue + exprDue + grammarDue + mistakes;
        if (due <= 0) return const SizedBox.shrink();
        return Semantics(
          button: true,
          label: AppStrings.homeDueChipLabel,
          child: InkWell(
            onTap: () => getIt<TabRouter>().switchTo(TabDestination.play),
            borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
                border: Border.all(color: TurnaTheme.glassBorder(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.menu_book_rounded,
                      color: TurnaTheme.brandTeal, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '$due',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: TurnaTheme.brandTeal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
        border: Border.all(
          color: TurnaTheme.glassBorder(context),
          width: 1,
        ),
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
                return Text(AppStrings.emDash);
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
  const ScoreCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: TurnaTheme.scoreChipBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
        border: Border.all(
          color: TurnaTheme.glassBorder(context),
          width: 1,
        ),
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
                return Text(AppStrings.emDash);
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
    super.key,
    required this.target,
    required this.style,
  });

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
