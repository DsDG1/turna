// Flutter imports:
import 'dart:convert';

// Package imports:
import 'package:drift/drift.dart' hide Expression;

// Project imports:
import 'package:varnamala/core/logger.dart';
import 'package:varnamala/data/course_database.dart' as db;
import 'package:varnamala/data/course_database_seeder.dart';
import 'package:varnamala/domain/course/expression.dart';
import 'package:varnamala/domain/course/grammar_point.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/lesson_content.dart';
import 'package:varnamala/domain/course/section.dart';
import 'package:varnamala/domain/course/unit.dart';
import 'package:varnamala/domain/course/word_entry.dart';
import 'package:varnamala/domain/repositories/i_course_repository.dart';

/// Reads course content from [CourseDatabase] and reconstructs the existing
/// freezed domain models ([Section]/[Unit]/[Lesson]/[LessonContent]/
/// [WordEntry]). This is the data-access layer `SwahiliCourse` calls instead
/// of `rootBundle`.
///
/// Section bodies are rebuilt with 4 ordered queries (section, units, lessons,
/// lesson content blobs) and grouped in Dart; lesson content is a pure
/// `LessonContent.fromJson(jsonDecode(blob))` since the seeder stores
/// normalized content.
class CourseRepository implements ICourseRepository {
  final db.CourseDatabase database;
  CourseRepository(this.database);

  /// Lightweight section shells (id/name/description/prerequisiteSectionIds,
  /// `units` empty) in on-disk order.
  @override
  Future<List<Section>> sectionShells() async {
    final rows = await (database.select(database.sections)
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return [
      for (final r in rows)
        Section(
          id: r.id,
          name: r.name,
          description: r.description,
          prerequisiteSectionIds:
              _decodeStringList(r.prerequisiteSectionIds),
          units: const <Unit>[],
        ),
    ];
  }

  /// Full vocabulary list.
  @override
  Future<List<WordEntry>> vocabulary() async {
    final rows = await database.select(database.vocabulary).get();
    return [
      for (final r in rows)
        WordEntry(
          id: r.id,
          term: r.term,
          translation: r.translation,
          pronunciation: r.pronunciation,
          audioAsset: r.audioAsset,
          tags: _decodeStringList(r.tags),
        ),
    ];
  }

  /// All grammar points.
  @override
  Future<List<GrammarPoint>> grammarPoints() async {
    final rows = await database.select(database.grammarPoints).get();
    return [for (final r in rows) _toGrammarPoint(r)];
  }

  /// A single grammar point by id, or `null` if unknown.
  @override
  Future<GrammarPoint?> grammarPointById(String id) async {
    final row = await (database.select(database.grammarPoints)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toGrammarPoint(row);
  }

  /// All expressions / phrases.
  @override
  Future<List<Expression>> expressions() async {
    final rows = await database.select(database.expressions).get();
    return [for (final r in rows) _toExpression(r)];
  }

  /// A single expression by id, or `null` if unknown.
  @override
  Future<Expression?> expressionById(String id) async {
    final row = await (database.select(database.expressions)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toExpression(row);
  }

  GrammarPoint _toGrammarPoint(db.GrammarPoint row) {
    return GrammarPoint(
      id: row.id,
      title: row.title,
      explanation: row.explanation,
      exampleExpressionIds: _decodeStringList(row.exampleExpressionIds),
      exampleSentenceIds: _decodeStringList(row.exampleSentenceIds),
      practiceItems:
          _decodePracticeItems(row.practiceItems, owner: 'grammar point ${row.id}'),
    );
  }

  Expression _toExpression(db.ExpressionEntry row) {
    return Expression(
      id: row.id,
      term: row.term,
      translation: row.translation,
      pronunciation: row.pronunciation,
      audioAsset: row.audioAsset,
      tags: _decodeStringList(row.tags),
    );
  }

  /// Decode the stored practice-item JSON for a grammar point. A corrupted
  /// column degrades to an empty practice list but is logged with [owner]
  /// (e.g. the grammar point id) so the corruption is observable instead of
  /// silently swallowed.
  List<Interaction> _decodePracticeItems(String raw, {required String owner}) {
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Interaction.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      logger.w('Corrupted practiceItems for $owner, treating as empty: $e');
      return const <Interaction>[];
    }
  }

  /// Rebuild a full [Section] (units → lessons → content) by id. Throws
  /// [ArgumentError] if the section id is unknown.
  @override
  Future<Section> section(String id) async {
    final sectionRow = await (database.select(database.sections)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (sectionRow == null) {
      throw ArgumentError('Unknown section id: $id');
    }

    final unitRows = await (database.select(database.units)
          ..where((t) => t.sectionId.equals(id))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();

    final lessonsByUnit = <String, List<Lesson>>{};
    if (unitRows.isNotEmpty) {
      final unitIds = unitRows.map((u) => u.id).toList();
      final lessonRows = await (database.select(database.lessons)
            ..where((t) => t.unitId.isIn(unitIds))
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();

      if (lessonRows.isNotEmpty) {
        final lessonIds = lessonRows.map((l) => l.id).toList();
        final contentRows = await (database.select(database.lessonContents)
              ..where((t) => t.lessonId.isIn(lessonIds)))
            .get();
        final contentByLesson = {
          for (final c in contentRows) c.lessonId: c.contentJson,
        };

        for (final lr in lessonRows) {
          final lesson = _toLesson(lr, contentByLesson[lr.id]);
          lessonsByUnit.putIfAbsent(lr.unitId, () => []).add(lesson);
        }
      }
    }

    final units = [
      for (final u in unitRows)
        Unit(
          id: u.id,
          name: u.name,
          description: u.description,
          prerequisiteUnitIds: _decodeStringList(u.prerequisiteUnitIds),
          lessons: lessonsByUnit[u.id] ?? const <Lesson>[],
        ),
    ];

    return Section(
      id: sectionRow.id,
      name: sectionRow.name,
      description: sectionRow.description,
      prerequisiteSectionIds:
          _decodeStringList(sectionRow.prerequisiteSectionIds),
      units: units,
    );
  }

  /// Rebuild a single [Lesson] by id (the new "Lesson by ID" capability).
  /// Throws [ArgumentError] if the lesson id is unknown.
  @override
  Future<Lesson> lessonById(String id) async {
    final row = await (database.select(database.lessons)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw ArgumentError('Unknown lesson id: $id');
    }
    final contentRow = await (database.select(database.lessonContents)
          ..where((t) => t.lessonId.equals(id)))
        .getSingleOrNull();
    return _toLesson(row, contentRow?.contentJson);
  }

  /// The stored course content version (composite `index+expressions`, written
  /// by [DatabaseSeeder] after seeding), or `null` if the DB has not been
  /// seeded yet. Used by the content-update prompt (ADR 0002) to detect
  /// version bumps.
  Future<String?> contentVersion() async {
    final row = await (database.select(database.courseMeta)
          ..where((t) => t.key.equals(DatabaseSeeder.metaContentVersion)))
        .getSingleOrNull();
    return row?.value;
  }

  Lesson _toLesson(db.Lesson row, String? contentJson) {
    LessonContent content;
    if (contentJson == null) {
      content = const LessonContent();
    } else {
      try {
        content = LessonContent.fromJson(
          jsonDecode(contentJson) as Map<String, dynamic>,
        );
      } catch (e) {
        // Corrupted content blob (partial write / migration glitch): degrade
        // to an empty LessonContent instead of crashing section()/lessonById()
        // for the whole row. Mirrors _decodePracticeItems / _decodeStringList.
        logger.w('Corrupted content for lesson ${row.id}, treating as empty: $e');
        content = const LessonContent();
      }
    }
    return Lesson(
      id: row.id,
      name: row.name,
      description: row.description,
      type: LessonType.values.byName(row.type),
      template: LessonTemplate.values.byName(row.template),
      prerequisiteLessonIds: _decodeStringList(row.prerequisiteLessonIds),
      content: content,
    );
  }

  List<String> _decodeStringList(String encoded) {
    try {
      final list = jsonDecode(encoded);
      return (list as List).map((e) => e as String).toList(growable: false);
    } catch (e) {
      // Corrupted column (migration glitch / partial write) degrades to empty
      // rather than crashing section/lesson load. Mirrors _decodePracticeItems.
      logger.w('Corrupted string list, treating as empty: $e');
      return const <String>[];
    }
  }
}