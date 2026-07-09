// Project imports:
import 'package:words625/courses/course_loader.dart';
import 'package:words625/domain/course/grammar_point.dart';

/// Swahili grammar points for the grammar-review SRS queue.
///
/// Grammar points are bundled in `assets/courses/swahili/grammar_points.json`,
/// seeded into the local SQLite DB, and loaded asynchronously at app start by
/// [SwahiliCourse.load]. The synchronous lookup [swahiliGrammarPointById] is
/// populated as a side-effect of the first call to [loadSwahiliGrammarPoints]
/// and remains valid for the rest of the session — the grammar review screen
/// can use it without awaiting any future.
Future<List<GrammarPoint>> loadSwahiliGrammarPoints() async {
  final course = await SwahiliCourse.load();
  _populateGrammarLookups(course);
  return course.grammarPoints;
}

void _populateGrammarLookups(SwahiliCourse course) {
  swahiliGrammarPointById
    ..clear()
    ..addAll(course.grammarPointsById);
}

/// Synchronous lookup-by-id map, populated on first [loadSwahiliGrammarPoints]
/// call. Read by the grammar review screen (which has no async context in
/// `build()`).
final Map<String, GrammarPoint> swahiliGrammarPointById =
    <String, GrammarPoint>{};