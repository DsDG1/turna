// Flutter imports:
import 'package:flutter/cupertino.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/core/logger.dart';
import 'package:words625/courses/languages/kannada.dart';
import 'package:words625/domain/course/section.dart';
import 'package:words625/domain/course/unit.dart';
import 'package:words625/domain/course/lesson.dart';

@injectable
class CourseProvider extends ChangeNotifier {
  // --- Section hierarchy ---
  List<Section> sections = [];
  int currentSectionIndex = 0;
  int? selectedUnitIndex;
  int? selectedLessonIndex;

  Section? get currentSection =>
      sections.isNotEmpty && currentSectionIndex < sections.length
          ? sections[currentSectionIndex]
          : null;

  Unit? get currentUnit {
    final section = currentSection;
    if (section == null || selectedUnitIndex == null) return null;
    if (selectedUnitIndex! >= section.units.length) return null;
    return section.units[selectedUnitIndex!];
  }

  Lesson? get currentLesson {
    final unit = currentUnit;
    if (unit == null || selectedLessonIndex == null) return null;
    if (selectedLessonIndex! >= unit.lessons.length) return null;
    return unit.lessons[selectedLessonIndex!];
  }

  List<Unit> get currentUnits => currentSection?.units ?? [];

  /// Look up a [Lesson] by its ID across all sections.
  Lesson? findLessonById(String id) {
    for (final section in sections) {
      for (final unit in section.units) {
        for (final lesson in unit.lessons) {
          if (lesson.id == id) return lesson;
        }
      }
    }
    return null;
  }

  /// Loads the Kannada section data. Called once on app start / language init.
  Future<void> getCourses() async {
    logger.w("Loading Kannada sections");
    sections = getKannadaSections();
    selectedUnitIndex = null;
    selectedLessonIndex = null;
    notifyListeners();
  }

  void switchToSection(int index) {
    if (index >= 0 && index < sections.length) {
      currentSectionIndex = index;
      selectedUnitIndex = null;
      selectedLessonIndex = null;
      notifyListeners();
    }
  }

  void selectUnit(int index) {
    if (index >= 0 && index < currentUnits.length) {
      selectedUnitIndex = index;
      selectedLessonIndex = null;
      notifyListeners();
    }
  }

  void selectLesson(int unitIndex, int lessonIndex) {
    if (unitIndex >= 0 && unitIndex < currentUnits.length) {
      final unit = currentUnits[unitIndex];
      if (lessonIndex >= 0 && lessonIndex < unit.lessons.length) {
        selectedUnitIndex = unitIndex;
        selectedLessonIndex = lessonIndex;
        notifyListeners();
      }
    }
  }
}
