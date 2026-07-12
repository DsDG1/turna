// Project imports:
import 'package:varnamala/courses/course_loader.dart';
import 'package:varnamala/domain/course/expression.dart';

/// Loads the full expression list into memory and exposes a synchronous
/// id lookup map used by renderers / review UI.
///
/// Called once during [setupLocator] after the course DB is seeded.
Future<List<Expression>> loadExpressions() async {
  final course = await CourseLoader.load();
  _populateExpressionLookups(course);
  return course.expressions;
}

void _populateExpressionLookups(CourseLoader course) {
  expressionsById
    ..clear()
    ..addAll(course.expressionsById);
}

/// Global synchronous lookup from expression id to [Expression].
///
/// Populated once at startup; empty until [loadExpressions] completes.
final Map<String, Expression> expressionsById = <String, Expression>{};