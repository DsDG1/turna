// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/progress_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/weak_word_quiz_assembler.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/theme.dart';
import 'components/section_switcher.dart';

class CourseTree extends StatefulWidget {
  const CourseTree({super.key});

  @override
  State<CourseTree> createState() => _CourseTreeState();
}

class _CourseTreeState extends State<CourseTree>
    with SingleTickerProviderStateMixin {
  static const _motionDuration = Duration(milliseconds: 200);

  /// Defensive section loads already scheduled for the next frame.
  final Set<String> _scheduledEnsure = {};

  /// Accordion state is kept per section, so changing sections does not make
  /// the learner lose the place they were working from.
  final Map<String, String?> _expandedUnitBySection = {};

  late final AnimationController _lessonRevealController;

  @override
  void initState() {
    super.initState();
    _lessonRevealController = AnimationController(
      vsync: this,
      duration: _motionDuration,
      value: 1,
    );
  }

  @override
  void dispose() {
    _lessonRevealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        context.select<AccessibilityProvider, bool>((p) => p.reducedMotion);

    return Container(
      decoration: BoxDecoration(
        gradient: TurnaTheme.courseTreeGradientFor(context),
      ),
      child: Selector<CourseProvider, _CourseSnapshot>(
        selector: (_, provider) => _CourseSnapshot.from(provider),
        shouldRebuild: _CourseSnapshot.shouldRebuild,
        builder: (context, snapshot, _) {
          if (!snapshot.hasSections) {
            if (snapshot.isLoaded) {
              return _buildErrorMessage(
                context,
                title: AppStrings.coursesCouldNotLoadCourse,
                error: AppStrings.coursesNoSectionsFound,
                onRetry: () => context.read<CourseProvider>().reloadCourse(),
              );
            }
            return const Center(child: _LoadingIndicator());
          }

          final currentId = snapshot.currentSectionId;
          if (currentId != null &&
              snapshot.loadState == SectionLoadState.initial) {
            _scheduleEnsureSection(context.read<CourseProvider>(), currentId);
          }

          final section = snapshot.section;
          if (section == null) return _buildEmptyMessage(context);

          return _buildSectionScrollView(
            context,
            snapshot: snapshot,
            section: section,
            reduceMotion: reduceMotion,
          );
        },
      ),
    );
  }

  void _scheduleEnsureSection(CourseProvider courseState, String id) {
    if (_scheduledEnsure.contains(id)) return;
    _scheduledEnsure.add(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      courseState.ensureSectionLoaded(id).whenComplete(() {
        _scheduledEnsure.remove(id);
      });
    });
  }

  Widget _buildSectionScrollView(
    BuildContext context, {
    required _CourseSnapshot snapshot,
    required Section section,
    required bool reduceMotion,
  }) {
    final bodySlivers = switch (snapshot.loadState) {
      SectionLoadState.initial || SectionLoadState.loading => <Widget>[
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _LoadingIndicator(),
          ),
        ],
      SectionLoadState.error => <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildErrorMessage(
              context,
              title: AppStrings.coursesCouldNotLoadSection,
              error: snapshot.error,
              onRetry: () =>
                  context.read<CourseProvider>().reloadSection(section.id),
            ),
          ),
        ],
      SectionLoadState.loaded when section.units.isEmpty => <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyMessage(context),
          ),
        ],
      SectionLoadState.loaded => _buildLoadedSlivers(
          context,
          section: section,
          reduceMotion: reduceMotion,
        ),
    };

    return CustomScrollView(
      key: PageStorageKey<String>('course-tree-${section.id}'),
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: SectionSwitcherHeaderDelegate(section: section),
        ),
        ...bodySlivers,
      ],
    );
  }

  List<Widget> _buildLoadedSlivers(
    BuildContext context, {
    required Section section,
    required bool reduceMotion,
  }) {
    final status = _resolveStatusProjection(context, section);
    final expandedUnitId = _expandedUnitBySection[section.id];

    final items = <_TreeItem>[];
    for (final unit in section.units) {
      final expanded = expandedUnitId == unit.id;
      items.add(
        _UnitHeaderItem(
          sectionId: section.id,
          unit: unit,
          dueLessonCount: status.dueCountByUnit[unit.id] ?? 0,
          weakLessonCount: status.weakCountByUnit[unit.id] ?? 0,
          expanded: expanded,
        ),
      );

      if (expanded) {
        for (var i = 0; i < unit.lessons.length; i++) {
          final lesson = unit.lessons[i];
          items.add(
            _LessonItem(
              sectionId: section.id,
              lesson: lesson,
              attention: status.attentionForLesson(lesson.id),
              isLast: i == unit.lessons.length - 1,
            ),
          );
        }
      }
    }

    final indexByKey = <Key, int>{
      for (var i = 0; i < items.length; i++) items[i].key: i,
    };

    return [
      SliverPadding(
        padding: EdgeInsets.only(
          top: 8,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
        ),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];
              final (top, bottom) = switch (item) {
                _UnitHeaderItem(expanded: final expanded) => (
                    4.0,
                    expanded ? 0.0 : 4.0
                  ),
                _LessonItem(isLast: final isLast) => (0.0, isLast ? 4.0 : 0.0),
              };

              final child = switch (item) {
                _UnitHeaderItem(
                  sectionId: final sectionId,
                  unit: final unit,
                  dueLessonCount: final dueCount,
                  weakLessonCount: final weakCount,
                  expanded: final expanded,
                ) =>
                  Selector<ProgressProvider, int>(
                    selector: (_, progress) {
                      var completed = 0;
                      for (final lesson in unit.lessons) {
                        if (progress.isLessonCompleted(lesson.id)) completed++;
                      }
                      return completed;
                    },
                    builder: (context, completedCount, _) => _UnitHeader(
                      unit: unit,
                      completedCount: completedCount,
                      dueLessonCount: dueCount,
                      weakLessonCount: weakCount,
                      expanded: expanded,
                      reduceMotion: reduceMotion,
                      onHeaderTap: () => _toggleUnit(
                        sectionId: sectionId,
                        unitId: unit.id,
                        expanded: expanded,
                        reduceMotion: reduceMotion,
                      ),
                    ),
                  ),
                _LessonItem(
                  lesson: final lesson,
                  attention: final attention,
                  isLast: final isLast,
                ) =>
                  _buildAnimatedLessonTile(
                    lesson: lesson,
                    attention: attention,
                    isLast: isLast,
                    reduceMotion: reduceMotion,
                  ),
              };

              return Padding(
                key: item.key,
                padding: EdgeInsets.fromLTRB(12, top, 12, bottom),
                child: child,
              );
            },
            childCount: items.length,
            findChildIndexCallback: (key) => indexByKey[key],
            addAutomaticKeepAlives: false,
          ),
        ),
      ),
    ];
  }

  Widget _buildAnimatedLessonTile({
    required Lesson lesson,
    required _Attention attention,
    required bool isLast,
    required bool reduceMotion,
  }) {
    Widget tile = Selector<ProgressProvider, ({bool completed, bool perfect})>(
      selector: (_, progress) => (
        completed: progress.isLessonCompleted(lesson.id),
        perfect: progress.isLessonPerfect(lesson.id),
      ),
      builder: (context, value, _) => _LessonTile(
        lesson: lesson,
        isCompleted: value.completed,
        isPerfect: value.perfect,
        attention: attention,
        isLast: isLast,
        onTap: () => _navigateToLesson(context, lesson),
      ),
    );

    if (reduceMotion) return tile;

    final reveal = _lessonRevealController.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );
    tile = FadeTransition(
      key: ValueKey<String>('lesson-reveal-${lesson.id}'),
      opacity: reveal,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(reveal),
        child: tile,
      ),
    );
    return tile;
  }

  _StatusProjection _resolveStatusProjection(
    BuildContext context,
    Section section,
  ) {
    Set<String> dueWordIds = const {};
    Set<String> weakWordIds = const {};
    final dueLessonIds = <String>{};
    final weakLessonIds = <String>{};

    try {
      dueWordIds = context.select((SrsProvider p) => p.dueWordIdSet);
      weakWordIds = WeakWordQuizAssembler.aggregateWeakWords(
        context.select((MistakeProvider p) => p.entries),
      ).map((word) => word.wordId).toSet();

      if (getIt.isRegistered<LessonLinkStore>()) {
        final store = getIt<LessonLinkStore>();
        for (final wordId in dueWordIds) {
          final link = store.linkFor(wordId);
          if (link != null) dueLessonIds.add(link.lessonId);
        }
        for (final wordId in weakWordIds) {
          final link = store.linkFor(wordId);
          if (link != null) weakLessonIds.add(link.lessonId);
        }
      }
    } catch (_) {
      // Lightweight widget tests and recovery surfaces may intentionally omit
      // review providers. The course remains usable without attention badges.
    }

    final lessonToUnit = <String, String>{};
    for (final unit in section.units) {
      for (final lesson in unit.lessons) {
        lessonToUnit[lesson.id] = unit.id;
      }
    }

    final dueCountByUnit = <String, int>{};
    final weakCountByUnit = <String, int>{};
    for (final lessonId in dueLessonIds) {
      final unitId = lessonToUnit[lessonId];
      if (unitId != null) {
        dueCountByUnit.update(unitId, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    for (final lessonId in weakLessonIds) {
      final unitId = lessonToUnit[lessonId];
      if (unitId != null) {
        weakCountByUnit.update(unitId, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    return _StatusProjection(
      dueLessonIds: dueLessonIds,
      weakLessonIds: weakLessonIds,
      dueCountByUnit: dueCountByUnit,
      weakCountByUnit: weakCountByUnit,
    );
  }

  void _toggleUnit({
    required String sectionId,
    required String unitId,
    required bool expanded,
    required bool reduceMotion,
  }) {
    setState(() {
      _expandedUnitBySection[sectionId] = expanded ? null : unitId;
    });

    if (!expanded) {
      if (reduceMotion) {
        _lessonRevealController.value = 1;
      } else {
        _lessonRevealController.forward(from: 0);
      }
    }
  }

  void _navigateToLesson(BuildContext context, Lesson lesson) {
    context.router.push(NewLessonRoute(lessonId: lesson.id));
  }

  Widget _buildEmptyMessage(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 64,
            color: TurnaTheme.textHintColor(context).withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            AppStrings.coursesNoUnitsAvailable,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage(
    BuildContext context, {
    required String title,
    required Object? error,
    required VoidCallback onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: TurnaTheme.error.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppStrings.commonRetry),
              style: ElevatedButton.styleFrom(
                backgroundColor: TurnaTheme.brandTeal,
                foregroundColor: TurnaTheme.textOnPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseSnapshot {
  final bool hasSections;
  final bool isLoaded;
  final String? currentSectionId;
  final Section? section;
  final SectionLoadState loadState;
  final Object? error;

  const _CourseSnapshot({
    required this.hasSections,
    required this.isLoaded,
    required this.currentSectionId,
    required this.section,
    required this.loadState,
    required this.error,
  });

  factory _CourseSnapshot.from(CourseProvider provider) {
    final currentSectionId = provider.currentSectionId;
    final loadState = currentSectionId == null
        ? SectionLoadState.initial
        : provider.sectionLoadState(currentSectionId);
    return _CourseSnapshot(
      hasSections: provider.sections.isNotEmpty,
      isLoaded: provider.isLoaded,
      currentSectionId: currentSectionId,
      section: provider.currentSection,
      loadState: loadState,
      error: currentSectionId == null
          ? null
          : provider.sectionLoadError(currentSectionId),
    );
  }

  static bool shouldRebuild(
    _CourseSnapshot previous,
    _CourseSnapshot next,
  ) =>
      previous.hasSections != next.hasSections ||
      previous.isLoaded != next.isLoaded ||
      previous.currentSectionId != next.currentSectionId ||
      !identical(previous.section, next.section) ||
      previous.loadState != next.loadState ||
      previous.error != next.error;
}

sealed class _TreeItem {
  const _TreeItem();

  Key get key;
}

class _UnitHeaderItem extends _TreeItem {
  final String sectionId;
  final Unit unit;
  final int dueLessonCount;
  final int weakLessonCount;
  final bool expanded;

  const _UnitHeaderItem({
    required this.sectionId,
    required this.unit,
    required this.dueLessonCount,
    required this.weakLessonCount,
    required this.expanded,
  });

  @override
  Key get key => ValueKey<String>('unit-$sectionId-${unit.id}');
}

class _LessonItem extends _TreeItem {
  final String sectionId;
  final Lesson lesson;
  final _Attention attention;
  final bool isLast;

  const _LessonItem({
    required this.sectionId,
    required this.lesson,
    required this.attention,
    required this.isLast,
  });

  @override
  Key get key => ValueKey<String>('lesson-$sectionId-${lesson.id}');
}

enum _Attention { none, due, weak }

class _StatusProjection {
  final Set<String> dueLessonIds;
  final Set<String> weakLessonIds;
  final Map<String, int> dueCountByUnit;
  final Map<String, int> weakCountByUnit;

  const _StatusProjection({
    required this.dueLessonIds,
    required this.weakLessonIds,
    required this.dueCountByUnit,
    required this.weakCountByUnit,
  });

  _Attention attentionForLesson(String lessonId) {
    if (dueLessonIds.contains(lessonId)) return _Attention.due;
    if (weakLessonIds.contains(lessonId)) return _Attention.weak;
    return _Attention.none;
  }
}

class _UnitHeader extends StatelessWidget {
  final Unit unit;
  final int completedCount;
  final int dueLessonCount;
  final int weakLessonCount;
  final bool expanded;
  final bool reduceMotion;
  final VoidCallback onHeaderTap;

  const _UnitHeader({
    required this.unit,
    required this.completedCount,
    required this.dueLessonCount,
    required this.weakLessonCount,
    required this.expanded,
    required this.reduceMotion,
    required this.onHeaderTap,
  });

  @override
  Widget build(BuildContext context) {
    final lessonCount = unit.lessons.length;
    final isFullyComplete =
        completedCount == lessonCount && unit.lessons.isNotEmpty;
    final attention = dueLessonCount > 0
        ? _Attention.due
        : weakLessonCount > 0
            ? _Attention.weak
            : _Attention.none;
    final attentionCount = attention == _Attention.due
        ? dueLessonCount
        : attention == _Attention.weak
            ? weakLessonCount
            : 0;
    final duration =
        reduceMotion ? Duration.zero : _CourseTreeState._motionDuration;
    final radius = Radius.circular(TurnaTheme.radiusMedium);
    final borderRadius = BorderRadius.vertical(
      top: radius,
      bottom: expanded ? Radius.zero : radius,
    );
    final progressText = AppStrings.coursesUnitProgress(
      completedCount,
      lessonCount,
    );
    final attentionText = _attentionText(attention, attentionCount);
    final semanticsParts = <String>[
      unit.name,
      progressText,
      if (attentionText != null) attentionText,
    ];

    return Semantics(
      button: true,
      expanded: expanded,
      label: semanticsParts.join('，'),
      onTap: onHeaderTap,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: TurnaTheme.cardBg(context),
          borderRadius: borderRadius,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onHeaderTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  final stacked = constraints.maxWidth < 328 || scale >= 1.3;
                  final title = _UnitTitle(unit: unit);
                  final progress = Text(
                    progressText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isFullyComplete
                          ? TurnaTheme.anatolianClay
                          : TurnaTheme.textSecondaryColor(context),
                    ),
                  );
                  final attentionChip = attention == _Attention.none
                      ? null
                      : _AttentionChip(
                          attention: attention,
                          count: attentionCount,
                        );
                  final chevron = AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 22,
                      color: TurnaTheme.textHintColor(context),
                    ),
                  );

                  if (stacked) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _UnitProgressRing(
                          completedCount: completedCount,
                          lessonCount: lessonCount,
                          reduceMotion: reduceMotion,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  progress,
                                  if (attentionChip != null) attentionChip,
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        chevron,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      _UnitProgressRing(
                        completedCount: completedCount,
                        lessonCount: lessonCount,
                        reduceMotion: reduceMotion,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: title),
                      const SizedBox(width: 10),
                      progress,
                      if (attentionChip != null) ...[
                        const SizedBox(width: 8),
                        attentionChip,
                      ],
                      const SizedBox(width: 4),
                      chevron,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnitTitle extends StatelessWidget {
  final Unit unit;

  const _UnitTitle({required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          unit.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: TurnaTheme.textPrimaryColor(context),
          ),
        ),
        if (unit.description.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            unit.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
        ],
      ],
    );
  }
}

class _UnitProgressRing extends StatelessWidget {
  final int completedCount;
  final int lessonCount;
  final bool reduceMotion;

  const _UnitProgressRing({
    required this.completedCount,
    required this.lessonCount,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    final progress = lessonCount == 0 ? 0.0 : completedCount / lessonCount;
    final complete = lessonCount > 0 && completedCount == lessonCount;
    final color = complete ? TurnaTheme.anatolianClay : TurnaTheme.brandTeal;

    return SizedBox.square(
      dimension: 40,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress),
        duration:
            reduceMotion ? Duration.zero : _CourseTreeState._motionDuration,
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.square(
              dimension: 38,
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 3,
                backgroundColor: TurnaTheme.dividerBg(context),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            Icon(
              complete ? Icons.check_rounded : Icons.menu_book_rounded,
              size: 18,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttentionChip extends StatelessWidget {
  final _Attention attention;
  final int count;

  const _AttentionChip({required this.attention, required this.count});

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (attention) {
      _Attention.due => (
          TurnaTheme.warning.withValues(alpha: 0.14),
          TurnaTheme.warning,
          Icons.schedule_rounded,
        ),
      _Attention.weak => (
          TurnaTheme.error.withValues(alpha: 0.10),
          TurnaTheme.error,
          Icons.fitness_center_rounded,
        ),
      _Attention.none => (
          Colors.transparent,
          TurnaTheme.textSecondaryColor(context),
          Icons.circle_outlined,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 4),
          Text(
            _attentionText(attention, count) ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  final Lesson lesson;
  final bool isCompleted;
  final bool isPerfect;
  final _Attention attention;
  final bool isLast;
  final VoidCallback onTap;

  const _LessonTile({
    required this.lesson,
    required this.isCompleted,
    required this.isPerfect,
    required this.attention,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomRadius =
        isLast ? const Radius.circular(TurnaTheme.radiusMedium) : Radius.zero;
    final borderRadius = BorderRadius.vertical(bottom: bottomRadius);
    final attentionText = _attentionText(attention, 1);
    final semanticsParts = <String>[
      lesson.name,
      _lessonTypeLabel(lesson.type),
      if (isPerfect)
        AppStrings.coursesPerfect
      else if (isCompleted)
        AppStrings.commonDone,
      if (attentionText != null) attentionText,
    ];

    return Semantics(
      button: true,
      label: semanticsParts.join('，'),
      onTap: onTap,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TurnaTheme.cardBg(context),
          borderRadius: borderRadius,
          border: Border(
            top: BorderSide(color: TurnaTheme.dividerBg(context)),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _LessonTypeIcon(
                    type: lesson.type,
                    completed: isCompleted,
                    perfect: isPerfect,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      lesson.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isCompleted
                            ? TurnaTheme.textSecondaryColor(context)
                            : TurnaTheme.textPrimaryColor(context),
                      ),
                    ),
                  ),
                  if (attention != _Attention.none) ...[
                    const SizedBox(width: 8),
                    _AttentionChip(attention: attention, count: 1),
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: TurnaTheme.textHintColor(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LessonTypeIcon extends StatelessWidget {
  final LessonType type;
  final bool completed;
  final bool perfect;

  const _LessonTypeIcon({
    required this.type,
    required this.completed,
    required this.perfect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: TurnaTheme.brandTeal.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
                border: perfect
                    ? Border.all(
                        color: TurnaTheme.anatolianClay.withValues(alpha: 0.65),
                      )
                    : null,
              ),
              child: Icon(
                _lessonTypeIcon(type),
                size: 18,
                color: TurnaTheme.brandTeal,
              ),
            ),
          ),
          if (completed)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: TurnaTheme.anatolianClay,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: TurnaTheme.cardBg(context),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 9,
                  color: TurnaTheme.textOnPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String? _attentionText(_Attention attention, int count) => switch (attention) {
      _Attention.due => AppStrings.coursesDueLessons(count),
      _Attention.weak => AppStrings.coursesWeakLessons(count),
      _Attention.none => null,
    };

IconData _lessonTypeIcon(LessonType type) => switch (type) {
      LessonType.normal => Icons.menu_book_rounded,
      LessonType.listening => Icons.headphones_rounded,
      LessonType.reading => Icons.chrome_reader_mode_rounded,
      LessonType.review => Icons.replay_rounded,
      LessonType.challenge => Icons.emoji_events_rounded,
    };

String _lessonTypeLabel(LessonType type) => switch (type) {
      LessonType.normal => AppStrings.coursesLessonTypeNormal,
      LessonType.listening => AppStrings.coursesLessonTypeListening,
      LessonType.reading => AppStrings.coursesLessonTypeReading,
      LessonType.review => AppStrings.coursesLessonTypeReview,
      LessonType.challenge => AppStrings.coursesLessonTypeChallenge,
    };

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(
              TurnaTheme.brandTeal.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.coursesLoadingCourses,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: TurnaTheme.textHintColor(context),
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}
