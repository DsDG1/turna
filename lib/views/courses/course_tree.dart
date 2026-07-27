// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/progress_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/application/weak_word_quiz_assembler.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/unit.dart';
import 'package:varnamala/l10n/app_localizations.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/views/theme.dart';
import 'components/section_switcher.dart';

class CourseTree extends StatefulWidget {
  const CourseTree({Key? key}) : super(key: key);

  @override
  State<CourseTree> createState() => _CourseTreeState();
}

class _CourseTreeState extends State<CourseTree> {
  // CourseProvider.load() is called once at app startup (see main.dart).
  // This widget must NOT call load() from initState: a tab round-trip
  // (AnimatedSwitcher swap) would rebuild, re-fire initState, and historically
  // reset cached bodies back to shells — a blank Course Tree.
  //
  // Defensive body loads for SectionLoadState.initial are scheduled via
  // [addPostFrameCallback] only (see [_scheduleEnsureSection]) so they stay
  // idempotent and never re-enter [CourseProvider.load].

  /// Section ids already scheduled for a defensive [ensureSectionLoaded] call.
  final Set<String> _scheduledEnsure = {};

  /// Accordion: at most one unit expanded. The lesson list inside an expanded
  /// unit is virtualized by the outer [SliverList], so even 100+ lessons only
  /// build the tiles currently in the viewport.
  String? _expandedUnitId;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: VarnamalaTheme.courseTreeGradientFor(context),
      ),
      child: Consumer<CourseProvider>(
        builder: (context, courseState, _) {
          final sections = courseState.sections;

          if (sections.isEmpty) {
            // After load completes with zero shells, never spin forever —
            // that looked like a gray hang with no recovery path.
            if (courseState.isLoaded) {
              return _buildErrorMessage(
                context,
                title: AppLocalizations.of(context)!.coursesCouldNotLoadCourse,
                error: AppLocalizations.of(context)!.coursesNoSectionsFound,
                onRetry: () => courseState.reloadCourse(),
              );
            }
            return const Center(child: _LoadingIndicator());
          }

          // Defensive: if the current section is still initial (e.g. a non-main
          // entry path forgot to call ensureSectionLoaded), kick off a body
          // load. Coalesced + cached inside the provider; safe to re-enter.
          final currentId = courseState.currentSectionId;
          if (currentId != null &&
              courseState.sectionLoadState(currentId) ==
                  SectionLoadState.initial) {
            _scheduleEnsureSection(courseState, currentId);
          }

          return Column(
            children: [
              // Section switcher — top-left aligned
              const Align(
                alignment: Alignment.centerLeft,
                child: SectionSwitcher(),
              ),

              // Section content — _UnitHeader and _LessonTile handle their own
              // progress consumption inside the virtualized tree.
              Expanded(
                child: _buildUnitTree(courseState),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Schedules a one-shot body load after this frame so we never call
  /// provider methods synchronously during [build].
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

  /// Renders the units and lessons for the currently selected section.
  ///
  /// The tree is flattened into a single [SliverList] so that expanding a unit
  /// with many lessons still benefits from Flutter's lazy sliver building.
  /// Previously each unit card held a [ListView.builder] with [shrinkWrap:true],
  /// which forced every lesson tile to be built during layout.
  Widget _buildUnitTree(CourseProvider courseState) {
    final section = courseState.currentSection;
    if (section == null) {
      return _buildEmptyMessage(context);
    }

    final loadState = courseState.sectionLoadState(section.id);

    if (loadState == SectionLoadState.loading ||
        loadState == SectionLoadState.initial) {
      return const Center(child: _LoadingIndicator());
    }

    if (loadState == SectionLoadState.error) {
      return _buildErrorMessage(
        context,
        title: AppLocalizations.of(context)!.coursesCouldNotLoadSection,
        error: courseState.sectionLoadError(section.id),
        onRetry: () => courseState.reloadSection(section.id),
      );
    }

    if (section.units.isEmpty) {
      return _buildEmptyMessage(context);
    }

    final progress = context.read<ProgressProvider>();
    // Status badges: O(due+weak words) via linkFor, not O(all links).
    Set<String> dueWordIds = const {};
    Set<String> weakWordIds = const {};
    final lessonIdsWithDue = <String>{};
    final lessonIdsWithWeak = <String>{};
    try {
      dueWordIds = context.select((SrsProvider p) => p.dueWordIdSet);
      weakWordIds = WeakWordQuizAssembler.aggregateWeakWords(
        context.select((MistakeProvider p) => p.entries),
      ).map((w) => w.wordId).toSet();
      if (getIt.isRegistered<LessonLinkStore>()) {
        final store = getIt<LessonLinkStore>();
        for (final wordId in dueWordIds) {
          final link = store.linkFor(wordId);
          if (link != null) lessonIdsWithDue.add(link.lessonId);
        }
        for (final wordId in weakWordIds) {
          final link = store.linkFor(wordId);
          if (link != null) lessonIdsWithWeak.add(link.lessonId);
        }
      }
    } catch (_) {
      // ProviderNotFound / empty DI — tree still renders without status dots.
    }

    // Single pass over section: completedCount per unit + lessonId→unit index.
    // Replaces the previous per-unit .where().length + 2×.any pattern whose
    // total cost was O(3 × section lessons). due/weak unit flags are now
    // resolved by reverse-looking up the due/weak lessonId sets through the
    // index — O(section lessons + due + weak) instead of O(section lessons
    // per badge).
    final completedCountByUnit = <String, int>{};
    final lessonToUnit = <String, String>{};
    for (final unit in section.units) {
      var count = 0;
      for (final lesson in unit.lessons) {
        lessonToUnit[lesson.id] = unit.id;
        if (progress.isLessonCompleted(lesson.id)) count++;
      }
      completedCountByUnit[unit.id] = count;
    }

    final unitsWithDue = <String>{};
    final unitsWithWeak = <String>{};
    for (final lessonId in lessonIdsWithDue) {
      final uid = lessonToUnit[lessonId];
      if (uid != null) unitsWithDue.add(uid);
    }
    for (final lessonId in lessonIdsWithWeak) {
      final uid = lessonToUnit[lessonId];
      if (uid != null) unitsWithWeak.add(uid);
    }

    // Flatten section into a single virtualized list of headers and lessons.
    final items = <_TreeItem>[];
    for (final unit in section.units) {
      final expanded = _expandedUnitId == unit.id;

      items.add(
        _UnitHeaderItem(
          unit: unit,
          completedCount: completedCountByUnit[unit.id] ?? 0,
          hasDue: unitsWithDue.contains(unit.id),
          hasWeak: unitsWithWeak.contains(unit.id),
          expanded: expanded,
        ),
      );

      if (expanded) {
        for (var i = 0; i < unit.lessons.length; i++) {
          items.add(
            _LessonItem(
              unit: unit,
              lesson: unit.lessons[i],
              isFirst: i == 0,
              isLast: i == unit.lessons.length - 1,
              lessonIdsWithDue: lessonIdsWithDue,
              lessonIdsWithWeak: lessonIdsWithWeak,
            ),
          );
        }
      }
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 8, bottom: 40),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                final (top, bottom) = switch (item) {
                  _UnitHeaderItem(expanded: final expanded) =>
                    (4.0, expanded ? 0.0 : 4.0),
                  _LessonItem(isLast: final isLast) =>
                    (0.0, isLast ? 4.0 : 0.0),
                };

                // RepaintBoundary isolates each item's painting so a progress
                // or selection notification repaints only the changed tile,
                // not the whole visible list.
                return RepaintBoundary(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, top, 12, bottom),
                    child: switch (item) {
                      _UnitHeaderItem(
                        unit: final unit,
                        completedCount: final completedCount,
                        hasDue: final hasDue,
                        hasWeak: final hasWeak,
                        expanded: final expanded,
                      ) =>
                        _UnitHeader(
                          unit: unit,
                          completedCount: completedCount,
                          hasDue: hasDue,
                          hasWeak: hasWeak,
                          expanded: expanded,
                          onHeaderTap: () {
                            setState(() {
                              _expandedUnitId =
                                  expanded ? null : unit.id;
                            });
                          },
                        ),
                      _LessonItem(
                        lesson: final lesson,
                        isFirst: final isFirst,
                        isLast: final isLast,
                        lessonIdsWithDue: final dueSet,
                        lessonIdsWithWeak: final weakSet,
                      ) =>
                        Selector<ProgressProvider,
                            ({bool completed, bool perfect})>(
                          selector: (_, progress) => (
                            completed:
                                progress.isLessonCompleted(lesson.id),
                            perfect: progress.isLessonPerfect(lesson.id),
                          ),
                          builder: (context, value, _) => _LessonTile(
                            lesson: lesson,
                            isCompleted: value.completed,
                            isPerfect: value.perfect,
                            hasDue: dueSet.contains(lesson.id),
                            hasWeak: weakSet.contains(lesson.id),
                            isFirst: isFirst,
                            isLast: isLast,
                            onTap: () =>
                                _navigateToLesson(context, lesson),
                          ),
                        ),
                    },
                  ),
                );
              },
              childCount: items.length,
            ),
          ),
        ),
      ],
    );
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
            color: VarnamalaTheme.textHint.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.coursesNoUnitsAvailable,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textSecondaryColor(context),
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
              color: VarnamalaTheme.error.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: VarnamalaTheme.textPrimaryColor(context),
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
                      color: VarnamalaTheme.textSecondaryColor(context),
                    ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppLocalizations.of(context)!.commonRetry),
              style: ElevatedButton.styleFrom(
                backgroundColor: VarnamalaTheme.peacockTeal,
                foregroundColor: VarnamalaTheme.textOnPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    VarnamalaTheme.radiusMedium,
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

/// Items in the flattened course tree. Using a sealed family keeps the
/// [SliverChildBuilderDelegate] type-safe and makes it obvious which data each
/// row needs.
sealed class _TreeItem {
  const _TreeItem();
}

class _UnitHeaderItem extends _TreeItem {
  const _UnitHeaderItem({
    required this.unit,
    required this.completedCount,
    required this.hasDue,
    required this.hasWeak,
    required this.expanded,
  });

  final Unit unit;
  final int completedCount;
  final bool hasDue;
  final bool hasWeak;
  final bool expanded;
}

class _LessonItem extends _TreeItem {
  const _LessonItem({
    required this.unit,
    required this.lesson,
    required this.isFirst,
    required this.isLast,
    required this.lessonIdsWithDue,
    required this.lessonIdsWithWeak,
  });

  final Unit unit;
  final Lesson lesson;
  final bool isFirst;
  final bool isLast;
  final Set<String> lessonIdsWithDue;
  final Set<String> lessonIdsWithWeak;
}

/// A tappable unit header displayed inside the virtualized course tree.
///
/// When [expanded] is true the bottom corners are squared off so the header
/// visually connects to the lesson tiles below it.
class _UnitHeader extends StatelessWidget {
  final Unit unit;
  final int completedCount;
  final bool hasDue;
  final bool hasWeak;
  final bool expanded;
  final VoidCallback onHeaderTap;

  const _UnitHeader({
    required this.unit,
    required this.completedCount,
    required this.hasDue,
    required this.hasWeak,
    required this.expanded,
    required this.onHeaderTap,
  });

  @override
  Widget build(BuildContext context) {
    final isFullyComplete =
        completedCount == unit.lessons.length && unit.lessons.isNotEmpty;
    final radiusMedium =
        const Radius.circular(VarnamalaTheme.radiusMedium);

    final borderRadius = BorderRadius.vertical(
      top: radiusMedium,
      bottom: expanded ? Radius.zero : radiusMedium,
    );

    return Material(
      color: VarnamalaTheme.cardBg(context),
      borderRadius: borderRadius,
      elevation: 0,
      shadowColor: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: borderRadius,
            onTap: onHeaderTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isFullyComplete
                          ? VarnamalaTheme.success.withValues(alpha: 0.18)
                          : VarnamalaTheme.peacockTeal
                              .withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(VarnamalaTheme.radiusSmall),
                    ),
                    child: Icon(
                      isFullyComplete
                          ? Icons.check_circle_rounded
                          : (expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded),
                      color: isFullyComplete
                          ? VarnamalaTheme.successDark
                          : VarnamalaTheme.peacockTeal,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          unit.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: VarnamalaTheme.textPrimaryColor(context),
                          ),
                        ),
                        if (unit.description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            unit.description,
                            style: TextStyle(
                              fontSize: 13,
                              color: VarnamalaTheme.textSecondaryColor(
                                  context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isFullyComplete
                          ? VarnamalaTheme.success.withValues(alpha: 0.12)
                          : VarnamalaTheme.peacockTeal
                              .withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.circular(VarnamalaTheme.radiusRound),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.coursesUnitProgress(
                        completedCount,
                        unit.lessons.length,
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isFullyComplete
                            ? VarnamalaTheme.successDark
                            : VarnamalaTheme.peacockTeal,
                      ),
                    ),
                  ),
                  if (hasDue || hasWeak) ...[
                    const SizedBox(width: 6),
                    if (hasDue)
                      const Icon(Icons.schedule_rounded,
                          size: 16, color: VarnamalaTheme.warning),
                    if (hasWeak)
                      const Icon(Icons.fitness_center_rounded,
                          size: 16, color: VarnamalaTheme.error),
                  ],
                ],
              ),
            ),
          ),
          if (expanded) const Divider(height: 1),
        ],
      ),
    );
  }
}

/// A tappable tile for a single Lesson.
///
/// When rendered as part of an expanded unit, [isFirst] and [isLast] control
/// the border radius so the tile visually connects to the unit header and to
/// the other lesson tiles in the same unit.
class _LessonTile extends StatelessWidget {
  final Lesson lesson;
  final bool isCompleted;
  final bool isPerfect;
  final bool hasDue;
  final bool hasWeak;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  const _LessonTile({
    required this.lesson,
    required this.isCompleted,
    required this.isPerfect,
    required this.hasDue,
    required this.hasWeak,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final typeColor = _lessonTypeColor(lesson.type);
    // Priority: completed > due > weak > default type color.
    Color iconBg;
    Color iconColor;
    IconData icon;
    if (isCompleted) {
      iconBg = VarnamalaTheme.success.withValues(alpha: 0.18);
      iconColor = VarnamalaTheme.successDark;
      icon = Icons.check_circle_rounded;
    } else if (hasDue) {
      iconBg = VarnamalaTheme.warning.withValues(alpha: 0.18);
      iconColor = VarnamalaTheme.warning;
      icon = Icons.schedule_rounded;
    } else if (hasWeak) {
      iconBg = VarnamalaTheme.error.withValues(alpha: 0.12);
      iconColor = VarnamalaTheme.error;
      icon = Icons.fitness_center_rounded;
    } else {
      iconBg = typeColor.withValues(alpha: 0.1);
      iconColor = typeColor;
      icon = _lessonTypeIcon(lesson.type);
    }

    final radiusMedium =
        const Radius.circular(VarnamalaTheme.radiusMedium);
    final borderRadius = BorderRadius.vertical(
      top: Radius.zero,
      bottom: isLast ? radiusMedium : Radius.zero,
    );

    return Material(
      color: VarnamalaTheme.cardBg(context),
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Status-aware lesson icon
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusSmall),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 12),
              // Lesson name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isCompleted
                            ? VarnamalaTheme.textSecondaryColor(context)
                            : VarnamalaTheme.textPrimaryColor(context),
                      ),
                    ),
                    if (lesson.description.isNotEmpty)
                      Text(
                        lesson.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: VarnamalaTheme.textSecondaryColor(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Type badge (or perfect crown if perfect)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? VarnamalaTheme.success.withValues(alpha: 0.1)
                      : typeColor.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusRound),
                ),
                child: Text(
                  isPerfect
                      ? AppLocalizations.of(context)!.coursesPerfect
                      : _lessonTypeLabel(context, lesson.type),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isCompleted
                        ? VarnamalaTheme.successDark
                        : typeColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: VarnamalaTheme.textHint.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _lessonTypeIcon(LessonType type) {
    return switch (type) {
      LessonType.normal => Icons.menu_book_rounded,
      LessonType.listening => Icons.headphones_rounded,
      LessonType.reading => Icons.chrome_reader_mode_rounded,
      LessonType.review => Icons.replay_rounded,
      LessonType.challenge => Icons.emoji_events_rounded,
    };
  }

  static Color _lessonTypeColor(LessonType type) {
    return switch (type) {
      LessonType.normal => VarnamalaTheme.peacockTeal,
      LessonType.listening => VarnamalaTheme.peacockCyan,
      LessonType.reading => VarnamalaTheme.leagueAmethyst,
      LessonType.review => VarnamalaTheme.warning,
      LessonType.challenge => VarnamalaTheme.leagueRuby,
    };
  }

  static String _lessonTypeLabel(BuildContext context, LessonType type) {
    final l = AppLocalizations.of(context)!;
    return switch (type) {
      LessonType.normal => l.coursesLessonTypeNormal,
      LessonType.listening => l.coursesLessonTypeListening,
      LessonType.reading => l.coursesLessonTypeReading,
      LessonType.review => l.coursesLessonTypeReview,
      LessonType.challenge => l.coursesLessonTypeChallenge,
    };
  }
}

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
              VarnamalaTheme.peacockTeal.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppLocalizations.of(context)!.coursesLoadingCourses,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: VarnamalaTheme.textHintColor(context),
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}
