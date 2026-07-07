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

@injectable
class CourseProvider extends ChangeNotifier {
  List<List<Course>>? courses;

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
    notifyListeners();
  }
}