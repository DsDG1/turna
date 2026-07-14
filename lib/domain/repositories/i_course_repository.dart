// Project imports:
import 'package:varnamala/domain/course/expression.dart';
import 'package:varnamala/domain/course/grammar_point.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/section.dart';
import 'package:varnamala/domain/course/word_entry.dart';

/// Read API for course content (DB-backed cache over JSON assets).
///
/// Concrete: [CourseRepository]. Phase 21 defines the interface only —
/// DI still registers the concrete class (see ADR 0007).
///
/// Loading is split for scale (~10k lessons):
/// - [sectionShells] — L0 index (no units)
/// - [section] — L1 tree metadata (units/lessons, **empty** [Lesson.content])
/// - [lessonById] — L2 full body (content JSON)
abstract class ICourseRepository {
  Future<List<Section>> sectionShells();

  /// L1 section tree: units + lesson metadata only. [Lesson.content] is empty;
  /// load bodies with [lessonById].
  Future<Section> section(String id);

  /// L2: single lesson with full [LessonContent].
  Future<Lesson> lessonById(String id);

  /// Owning section id for [unitId], or `null` if the unit is unknown.
  Future<String?> sectionIdForUnit(String unitId);

  /// Owning section id for [lessonId], or `null` if the lesson is unknown.
  Future<String?> sectionIdForLesson(String lessonId);

  Future<List<WordEntry>> vocabulary();
  Future<List<GrammarPoint>> grammarPoints();
  Future<GrammarPoint?> grammarPointById(String id);
  Future<List<Expression>> expressions();
  Future<Expression?> expressionById(String id);
}
