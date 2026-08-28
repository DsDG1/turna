import 'package:turna/domain/course/course_scope.dart';

/// Which Play / Profile review queues a course scope may show (ADR 0037).
///
/// Typed [CourseScope] is the only discriminator. Wire-key overloads decode
/// with [CourseScopeCodec]; the sole leftover string inspection is the same
/// `anki:` legacy prefix used by [LanguagePlaygroundEligibility].
abstract final class PlayReviewEligibility {
  static bool isLanguage(CourseScope scope) => scope is BuiltinCourseScope;

  static bool isAnki(CourseScope scope) =>
      scope is OfficialAnkiCourseScope || scope is LegacyAnkiCourseScope;

  static bool isAnkiScope(String courseScope) {
    final decoded = CourseScopeCodec.decode(courseScope);
    if (decoded != null) return isAnki(decoded);
    return courseScope.startsWith('anki:');
  }

  static bool isLanguageScope(String courseScope) => !isAnkiScope(courseScope);
}
