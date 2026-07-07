// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:words625/application/course_provider.dart';
import 'package:words625/domain/course/lesson.dart';
import 'package:words625/domain/course/unit.dart';
import 'package:words625/routing/routing.gr.dart';
import 'package:words625/views/theme.dart';
import 'components/section_switcher.dart';

class CourseTree extends StatefulWidget {
  const CourseTree({Key? key}) : super(key: key);

  @override
  State<CourseTree> createState() => _CourseTreeState();
}

class _CourseTreeState extends State<CourseTree> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CourseProvider>().getCourses();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: VarnamalaTheme.courseTreeGradient,
      ),
      child: Consumer<CourseProvider>(
        builder: (context, courseState, _) {
          final sections = courseState.sections;

          if (sections.isEmpty) {
            return const Center(child: _LoadingIndicator());
          }

          return Column(
            children: [
              // Section switcher — top-left aligned
              const Align(
                alignment: Alignment.centerLeft,
                child: SectionSwitcher(),
              ),

              // Section content
              Expanded(
                child: _buildUnitTree(courseState),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Renders the units and lessons for the currently selected section.
  Widget _buildUnitTree(CourseProvider courseState) {
    final section = courseState.currentSection;
    if (section == null || section.units.isEmpty) {
      return _buildEmptyMessage();
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 8, bottom: 40),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final unit = section.units[index];
                return _UnitCard(
                  unit: unit,
                  onLessonTap: (lesson) {
                    // Navigate to new lesson screen via lesson ID.
                    // Route import is added after Step 4–5.
                    _navigateToLesson(context, lesson);
                  },
                );
              },
              childCount: section.units.length,
            ),
          ),
        ),
      ],
    );
  }

  void _navigateToLesson(BuildContext context, Lesson lesson) {
    context.router.push(NewLessonRoute(lessonId: lesson.id));
  }

  Widget _buildEmptyMessage() {
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
          const Text(
            'No units available',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A card displaying a Unit with its Lessons listed below.
class _UnitCard extends StatefulWidget {
  final Unit unit;
  final void Function(Lesson lesson) onLessonTap;

  const _UnitCard({
    required this.unit,
    required this.onLessonTap,
  });

  @override
  State<_UnitCard> createState() => _UnitCardState();
}

class _UnitCardState extends State<_UnitCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        elevation: 0,
        shadowColor: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unit header — tappable to expand/collapse
            InkWell(
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(VarnamalaTheme.radiusMedium),
                bottom: _expanded
                    ? Radius.zero
                    : const Radius.circular(VarnamalaTheme.radiusMedium),
              ),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color:
                            VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(
                            VarnamalaTheme.radiusSmall),
                      ),
                      child: Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: VarnamalaTheme.peacockTeal,
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
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: VarnamalaTheme.textPrimary,
                            ),
                          ),
                          if (unit.description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              unit.description,
                              style: const TextStyle(
                                fontSize: 13,
                                color: VarnamalaTheme.textSecondary,
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
                        color:
                            VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(
                            VarnamalaTheme.radiusRound),
                      ),
                      child: Text(
                        '${unit.lessons.length} lessons',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: VarnamalaTheme.peacockTeal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Lesson list — shown when expanded
            if (_expanded) ...[
              const Divider(height: 1),
              ...unit.lessons.map(
                (lesson) => _LessonTile(
                  lesson: lesson,
                  onTap: () => widget.onLessonTap(lesson),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A tappable tile for a single Lesson.
class _LessonTile extends StatelessWidget {
  final Lesson lesson;
  final VoidCallback onTap;

  const _LessonTile({
    required this.lesson,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Type icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _lessonTypeColor(lesson.type).withValues(alpha: 0.1),
                borderRadius:
                    BorderRadius.circular(VarnamalaTheme.radiusSmall),
              ),
              child: Icon(
                _lessonTypeIcon(lesson.type),
                size: 16,
                color: _lessonTypeColor(lesson.type),
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
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: VarnamalaTheme.textPrimary,
                    ),
                  ),
                  if (lesson.description.isNotEmpty)
                    Text(
                      lesson.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: VarnamalaTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Type badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _lessonTypeColor(lesson.type).withValues(alpha: 0.1),
                borderRadius:
                    BorderRadius.circular(VarnamalaTheme.radiusRound),
              ),
              child: Text(
                _lessonTypeLabel(lesson.type),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _lessonTypeColor(lesson.type),
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

  static String _lessonTypeLabel(LessonType type) {
    return switch (type) {
      LessonType.normal => 'Lesson',
      LessonType.listening => 'Listening',
      LessonType.reading => 'Reading',
      LessonType.review => 'Review',
      LessonType.challenge => 'Challenge',
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
          'Loading courses...',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: VarnamalaTheme.textHint,
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}
