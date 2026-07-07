// Flutter imports:
import 'package:flutter/cupertino.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/core/enums.dart';
import 'package:words625/core/logger.dart';
import 'package:words625/courses/courses.dart';
import 'package:words625/di/injection.dart';
import 'package:words625/domain/course/course.dart';
import 'package:words625/service/locator.dart';

/// Lightweight data class for a Section in the course tree.
/// Wraps existing [Course] data; does not need Freezed.
class SectionData {
  final String name;
  final List<Course> courses; // flattened list of courses in this section

  const SectionData({required this.name, required this.courses});
}

@injectable
class CourseProvider extends ChangeNotifier {
  List<List<Course>>? courses;

  // --- Section hierarchy ---
  List<SectionData> sections = [];
  int currentSectionIndex = 0;

  SectionData? get currentSection =>
      sections.isNotEmpty ? sections[currentSectionIndex] : null;

  Future<void> getCourses(TargetLanguage language) async {
    logger.w("Getting Courses for $language");
    final displayName = getIt<AppPrefs>().authUser.getValue().displayName;
    final firstName = (displayName == null || displayName.isEmpty)
        ? 'Friend'
        : displayName.split(" ").first;
    courses = await parseCourses(
      firstName: firstName,
      targetLanguage: language,
    );

    // Build section hierarchy from loaded courses.
    // Section 1 gets all existing courses; Section 2 is empty placeholder.
    _buildSections();

    notifyListeners();
  }

  void switchToSection(int index) {
    if (index >= 0 && index < sections.length) {
      currentSectionIndex = index;
      notifyListeners();
    }
  }

  /// Flattens [courses] groups into per-course entries for Section 1.
  void _buildSections() {
    final allCourses = <Course>[];
    if (courses != null) {
      for (final group in courses!) {
        allCourses.addAll(group);
      }
    }

    sections = [
      SectionData(name: 'Section 1', courses: allCourses),
      const SectionData(name: 'Section 2', courses: []),
    ];
  }
}