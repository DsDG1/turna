// Project imports:
import 'package:words625/courses/course_loader.dart';
import 'package:words625/domain/course/expression.dart';

/// Loads the full expression list into memory and exposes a synchronous
/// id lookup map used by renderers / review UI.
///
/// Called once during [setupLocator] after the course DB is seeded.
Future<List<Expression>> loadSwahiliExpressions() async {
  final course = await SwahiliCourse.load();
  _populateExpressionLookups(course);
  return course.expressions;
}

void _populateExpressionLookups(SwahiliCourse course) {
  swahiliExpressionsById
    ..clear()
    ..addAll(course.expressionsById);
}

/// Global synchronous lookup from expression id to [Expression].
///
/// Populated once at startup; empty until [loadSwahiliExpressions] completes.
final Map<String, Expression> swahiliExpressionsById = <String, Expression>{};
