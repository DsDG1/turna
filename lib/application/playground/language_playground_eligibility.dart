/// Single authoritative policy deciding whether the language Playground may
/// be shown or entered for a course scope.
///
/// Current course model has exactly two scope families: `''` (the built-in
/// language course) and `anki:<importId>` (an imported Anki deck — legacy
/// and Official-Anki projections both encode as `anki:` scopes), so a
/// prefix check is sufficient. When additional language course scopes are
/// introduced this must be upgraded to an explicit `CourseKind` enum instead
/// of overloading the scope string — "not built-in" must never silently
/// mean "language" or "Anki".
///
/// Every call site (Play Hub hero visibility, Playground page entry guard,
/// PlaygroundAssembler data filtering) must use this policy; do not write
/// ad-hoc `startsWith('anki:')` checks beside widgets or assemblers.
abstract final class LanguagePlaygroundEligibility {
  static bool isEligibleScope(String courseScope) =>
      !courseScope.startsWith('anki:');
}
