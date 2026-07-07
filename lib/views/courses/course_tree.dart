// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:words625/application/course_provider.dart';
import 'package:words625/application/language_provider.dart';
import 'package:words625/domain/course/course.dart';
import 'package:words625/views/theme.dart';
import 'components/course_node.dart';
import 'components/double_course_node.dart';
import 'components/triple_course_node.dart';
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
      final language = context.read<LanguageProvider>().selectedLanguage;
      context.read<CourseProvider>().getCourses(language);
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
          final courses = courseState.courses;
          final sectionIndex = courseState.currentSectionIndex;

          if (courses == null) {
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
                child: _buildSectionContent(courseState, sectionIndex),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Renders the content for the selected section.
  Widget _buildSectionContent(CourseProvider courseState, int sectionIndex) {
    if (sectionIndex == 0) {
      // Section 1 — existing course tree
      return _buildExistingCourseTree(courseState.courses!);
    } else {
      // Section 2+ — empty placeholder
      return _buildEmptySection(sectionIndex);
    }
  }

  /// The existing course tree rendering (unchanged from original).
  Widget _buildExistingCourseTree(List<List<Course>> courses) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 8, bottom: 40),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final courseIndex = index ~/ 2;
                final isConnector = index.isOdd;

                if (isConnector) {
                  if (courseIndex >= courses.length) {
                    return const SizedBox.shrink();
                  }
                  return _buildPathConnector();
                }

                if (courseIndex >= courses.length) {
                  return const SizedBox.shrink();
                }

                final courseGroup = courses[courseIndex];
                if (courseGroup.length == 1) {
                  return CourseNode(courseGroup[0], crown: 1);
                } else if (courseGroup.length == 2) {
                  return DoubleCourseNode(
                    CourseNode(courseGroup[0], crown: 1),
                    CourseNode(courseGroup[1], crown: 1),
                  );
                } else if (courseGroup.length == 3) {
                  return TripleCourseNode(
                    CourseNode(courseGroup[0]),
                    CourseNode(courseGroup[1]),
                    CourseNode(courseGroup[2]),
                  );
                }
                return const SizedBox.shrink();
              },
              childCount: courses.isEmpty ? 0 : courses.length * 2 - 1,
            ),
          ),
        ),
      ],
    );
  }

  /// Empty placeholder for sections with no content.
  Widget _buildEmptySection(int sectionIndex) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.construction_rounded,
            size: 64,
            color: VarnamalaTheme.textHint.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Section $sectionIndex',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming soon',
            style: TextStyle(
              fontSize: 14,
              color: VarnamalaTheme.textHint.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathConnector() {
    return Center(
      child: Container(
        width: 3,
        height: 28,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              VarnamalaTheme.peacockTeal.withValues(alpha: 0.3),
              VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
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
