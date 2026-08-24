import 'package:turna/domain/course/course_scope.dart';

/// Single authoritative policy deciding whether the language Playground may
/// be shown or entered for a course scope.
///
/// Scopes are typed (plan 34 D1): only the built-in language course is
/// Playground-eligible; Legacy Anki imports and Official Anki sources are
/// not. String inputs are accepted for call sites that still hold the
/// persisted wire key — they are decoded with [CourseScopeCodec], never
/// sniffed by prefix.
///
/// Every call site (Play Hub hero visibility, Playground page entry guard,
/// PlaygroundAssembler data filtering) must use this policy; do not write
/// ad-hoc scope-kind checks beside widgets or assemblers.
abstract final class LanguagePlaygroundEligibility {
  static bool isEligible(CourseScope scope) => scope is BuiltinCourseScope;

  static bool isEligibleScope(String courseScope) {
    final decoded = CourseScopeCodec.decode(courseScope);
    if (decoded != null) return isEligible(decoded);
    // Legacy persisted values: '' (builtin) and bare language ids are
    // eligible; 'anki:*' values are not. This is the only place legacy
    // strings are inspected.
    return !courseScope.startsWith('anki:');
  }
}
