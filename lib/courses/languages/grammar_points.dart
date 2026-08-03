// Project imports:
import 'package:turna/courses/course_loader.dart';
import 'package:turna/domain/course/grammar_point.dart';

/// Grammar points for the grammar-review SRS queue.
///
/// Grammar points are bundled in `assets/courses/turkish/grammar_points.json`,
/// seeded into the local SQLite DB, and loaded asynchronously at app start by
/// [CourseLoader.load]. The synchronous lookup [grammarPointById] is
/// populated as a side-effect of the first call to [loadGrammarPoints]
/// and remains valid for the rest of the session — the grammar review screen
/// can use it without awaiting any future.
Future<List<GrammarPoint>> loadGrammarPoints() async {
  final course = await CourseLoader.load();
  _populateGrammarLookups(course);
  return course.grammarPoints;
}

void _populateGrammarLookups(CourseLoader course) {
  grammarPointById
    ..clear()
    ..addAll(course.grammarPointsById);
}

/// Synchronous lookup-by-id map, populated on first [loadGrammarPoints]
/// call. Read by the grammar review screen (which has no async context in
/// `build()`).
final Map<String, GrammarPoint> grammarPointById =
    <String, GrammarPoint>{};