// Flutter imports:
import 'dart:convert';

// Package imports:
import 'package:drift/drift.dart' hide Expression;

// Project imports:
import 'package:words625/data/course_database.dart' as db;
import 'package:words625/domain/course/expression.dart';
import 'package:words625/domain/course/grammar_point.dart';
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/domain/course/lesson.dart';
import 'package:words625/domain/course/lesson_content.dart';
import 'package:words625/domain/course/section.dart';
import 'package:words625/domain/course/unit.dart';
import 'package:words625/domain/course/word_entry.dart';

/// Reads course content from [CourseDatabase] and reconstructs the existing
/// freezed domain models ([Section]/[Unit]/[Lesson]/[LessonContent]/
/// [WordEntry]). This is the data-access layer `SwahiliCourse` calls instead
/// of `rootBundle`.
///
/// Section bodies are rebuilt with 4 ordered queries (section, units, lessons,
/// lesson content blobs) and grouped in Dart; lesson content is a pure
/// `LessonContent.fromJson(jsonDecode(blob))` since the seeder stores
/// normalized content.
class CourseRepository {
  final db.CourseDatabase database;
  CourseRepository(this.database);

  /// Lightweight section shells (id/name/description/prerequisiteSectionIds,
  /// `units` empty) in on-disk order.
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
  Future<List<GrammarPoint>> grammarPoints() async {
    final rows = await database.select(database.grammarPoints).get();
    return [for (final r in rows) _toGrammarPoint(r)];
  }

  /// A single grammar point by id, or `null` if unknown.
  Future<GrammarPoint?> grammarPointById(String id) async {
    final row = await (database.select(database.grammarPoints)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toGrammarPoint(row);
  }

  /// All expressions / phrases.
  Future<List<Expression>> expressions() async {
    final rows = await database.select(database.expressions).get();
    return [for (final r in rows) _toExpression(r)];
  }

  /// A single expression by id, or `null` if unknown.
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
      practiceItems: _decodePracticeItems(row.practiceItems),
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

  List<Interaction> _decodePracticeItems(String raw) {
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Interaction.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const <Interaction>[];
    }
  }

  /// Rebuild a full [Section] (units → lessons → content) by id. Throws
  /// [ArgumentError] if the section id is unknown.
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

  Lesson _toLesson(db.Lesson row, String? contentJson) {
    return Lesson(
      id: row.id,
      name: row.name,
      description: row.description,
      type: LessonType.values.byName(row.type),
      template: LessonTemplate.values.byName(row.template),
      prerequisiteLessonIds: _decodeStringList(row.prerequisiteLessonIds),
      content: contentJson == null
          ? const LessonContent()
          : LessonContent.fromJson(
              jsonDecode(contentJson) as Map<String, dynamic>,
            ),
    );
  }

  List<String> _decodeStringList(String encoded) {
    final list = jsonDecode(encoded);
    return (list as List).map((e) => e as String).toList(growable: false);
  }
}