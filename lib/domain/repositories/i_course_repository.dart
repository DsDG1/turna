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
abstract class ICourseRepository {
  Future<List<Section>> sectionShells();
  Future<Section> section(String id);
  Future<Lesson> lessonById(String id);
  Future<List<WordEntry>> vocabulary();
  Future<List<GrammarPoint>> grammarPoints();
  Future<GrammarPoint?> grammarPointById(String id);
  Future<List<Expression>> expressions();
  Future<Expression?> expressionById(String id);
}
