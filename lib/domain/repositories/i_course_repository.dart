// Project imports:
import 'package:turna/data/course_database.dart' as db;
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/word_entry.dart';

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

  /// Load full lesson bodies whose `content_json` contains any of [needles]
  /// (substring match). Used by Anki review to resolve a small batch of
  /// word ids without loading an entire multi-thousand-card deck.
  ///
  /// Returns at most one [Lesson] per matching `lesson_id`. Empty [needles]
  /// yields an empty list.
  Future<List<Lesson>> lessonsContainingAny(Iterable<String> needles);

  /// Owning section id for [unitId], or `null` if the unit is unknown.
  Future<String?> sectionIdForUnit(String unitId);

  /// Owning section id for [lessonId], or `null` if the lesson is unknown.
  Future<String?> sectionIdForLesson(String lessonId);

  Future<List<WordEntry>> vocabulary();
  Future<List<GrammarPoint>> grammarPoints();
  Future<GrammarPoint?> grammarPointById(String id);
  Future<List<Expression>> expressions();
  Future<Expression?> expressionById(String id);

  /// Bulk-write a full section tree (units + lessons + lesson contents) in a
  /// single transaction, upserting by id. Used by importers (Anki decks);
  /// language courses still flow through the seeder.
  Future<void> bulkInsertCourseTree(Section section);

  /// Bulk-write vocabulary entries (upsert by id). Used by importers.
  Future<void> bulkInsertVocabulary(List<WordEntry> words);

  /// Delete vocabulary entries whose tags contain [tag] (exact list-element
  /// match on the JSON-encoded tags column). Returns the number of rows
  /// removed. Used to uninstall imported decks (`anki:<importId>` tag).
  Future<int> deleteByTag(String tag);

  /// Delete a section and its whole tree (units, lessons, lesson contents).
  Future<void> deleteSection(String sectionId);

  /// List all recorded Anki imports, most recent first.
  Future<List<db.AnkiImport>> ankiImports();
}
