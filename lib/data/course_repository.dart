// Flutter imports:
import 'dart:convert';

// Package imports:
import 'package:drift/drift.dart' hide Expression;

// Project imports:
import 'package:varnamala/core/logger.dart';
import 'package:varnamala/core/utils.dart';
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
import 'package:injectable/injectable.dart';
import 'package:varnamala/domain/repositories/i_course_repository.dart';

/// Reads course content from [CourseDatabase] and reconstructs the existing
/// freezed domain models ([Section]/[Unit]/[Lesson]/[LessonContent]/
/// [WordEntry]). This is the data-access layer `CourseLoader` calls instead
/// of `rootBundle`.
///
/// Section trees (L1) are rebuilt with 2–3 queries (section, units, lessons
/// via join) and **do not** load `lesson_contents` — that keeps opening a
/// section with ~1800 lessons free of giant `IN` lists and mass JSON decode.
/// Full bodies are loaded only via [lessonById] (L2).
@LazySingleton(as: ICourseRepository)
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
          level: r.level.isEmpty ? null : r.level,
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

  /// Rebuild an L1 [Section] tree (units → lesson **metadata** only) by id.
  ///
  /// [Lesson.content] is always empty here so course-tree open stays O(metadata)
  /// and never hits SQLite's ~999-variable `IN` limit on content ids. Use
  /// [lessonById] for full bodies. Throws [ArgumentError] if unknown.
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
      // Join on sectionId — single bind parameter, scales past 999 lessons.
      final lessonQuery = database.select(database.lessons).join([
        innerJoin(
          database.units,
          database.units.id.equalsExp(database.lessons.unitId),
        ),
      ])
        ..where(database.units.sectionId.equals(id))
        ..orderBy([
          OrderingTerm(expression: database.units.sortOrder),
          OrderingTerm(expression: database.lessons.sortOrder),
        ]);

      final joined = await lessonQuery.get();
      for (final row in joined) {
        final lr = row.readTable(database.lessons);
        // Metadata only — empty content is intentional for the course tree.
        final lesson = _toLesson(lr, null);
        lessonsByUnit.putIfAbsent(lr.unitId, () => []).add(lesson);
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
      level: sectionRow.level.isEmpty ? null : sectionRow.level,
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

  @override
  Future<String?> sectionIdForUnit(String unitId) async {
    final row = await (database.select(database.units)
          ..where((t) => t.id.equals(unitId)))
        .getSingleOrNull();
    return row?.sectionId;
  }

  @override
  Future<String?> sectionIdForLesson(String lessonId) async {
    final query = database.select(database.lessons).join([
      innerJoin(
        database.units,
        database.units.id.equalsExp(database.lessons.unitId),
      ),
    ])
      ..where(database.lessons.id.equals(lessonId))
      ..limit(1);
    final rows = await query.get();
    if (rows.isEmpty) return null;
    return rows.first.readTable(database.units).sectionId;
  }

  /// Bulk-write a full [Section] tree (section + units + lessons + lesson
  /// contents) in one transaction, upserting by id. Mirrors the write pattern
  /// of `AiCourseProvider._writeSectionToDb`; used by the Anki importer.
  @override
  Future<void> bulkInsertCourseTree(Section section) async {
    final sectionRows = await database.select(database.sections).get();
    final nextOrder = sectionRows.isEmpty
        ? 0
        : sectionRows
                .map((r) => r.sortOrder)
                .fold<int>(0, (a, b) => a > b ? a : b) +
            1;

    await database.transaction(() async {
      await database.into(database.sections).insertOnConflictUpdate(
            db.SectionsCompanion(
              id: Value(section.id),
              name: Value(section.name),
              description: Value(section.description),
              level: Value(section.level ?? ''),
              prerequisiteSectionIds:
                  Value(jsonEncode(section.prerequisiteSectionIds)),
              sortOrder: Value(nextOrder),
            ),
          );

      for (var uOrder = 0; uOrder < section.units.length; uOrder++) {
        final u = section.units[uOrder];
        await database.into(database.units).insertOnConflictUpdate(
              db.UnitsCompanion(
                id: Value(u.id),
                sectionId: Value(section.id),
                name: Value(u.name),
                description: Value(u.description),
                prerequisiteUnitIds:
                    Value(jsonEncode(u.prerequisiteUnitIds)),
                sortOrder: Value(uOrder),
              ),
            );
        for (var lOrder = 0; lOrder < u.lessons.length; lOrder++) {
          final l = u.lessons[lOrder];
          await database.into(database.lessons).insertOnConflictUpdate(
                db.LessonsCompanion(
                  id: Value(l.id),
                  unitId: Value(u.id),
                  name: Value(l.name),
                  description: Value(l.description),
                  type: Value(l.type.name),
                  template: Value(l.template.name),
                  prerequisiteLessonIds:
                      Value(jsonEncode(l.prerequisiteLessonIds)),
                  sortOrder: Value(lOrder),
                ),
              );
          await database.into(database.lessonContents).insertOnConflictUpdate(
                db.LessonContentsCompanion(
                  lessonId: Value(l.id),
                  contentJson: Value(jsonEncode(l.content.toJson())),
                ),
              );
        }
      }
    });
  }

  /// Bulk-upsert vocabulary entries in one transaction (Anki importer).
  @override
  Future<void> bulkInsertVocabulary(List<WordEntry> words) async {
    await database.transaction(() async {
      for (final w in words) {
        await database.into(database.vocabulary).insertOnConflictUpdate(
              db.VocabularyCompanion(
                id: Value(w.id),
                term: Value(w.term),
                translation: Value(w.translation),
                pronunciation: Value(w.pronunciation),
                audioAsset: Value(w.audioAsset),
                tags: Value(jsonEncode(w.tags)),
              ),
            );
      }
    });
  }

  /// Delete vocabulary entries whose JSON-encoded tags contain [tag] as an
  /// exact list element (`%"tag"%` LIKE match — the quotes keep `anki:x`
  /// from matching `anki:xyz`).
  @override
  Future<int> deleteByTag(String tag) async {
    return (database.delete(database.vocabulary)
          ..where((t) => t.tags.like('%"$tag"%')))
        .go();
  }

  /// Delete a section and its whole tree. Done manually (contents → lessons
  /// → units → section) instead of relying on the `ON DELETE CASCADE`
  /// constraints, which only fire when SQLite foreign-key enforcement is on.
  @override
  Future<void> deleteSection(String sectionId) async {
    await database.transaction(() async {
      final unitIds = await (database.select(database.units)
            ..where((t) => t.sectionId.equals(sectionId)))
          .map((u) => u.id)
          .get();
      if (unitIds.isNotEmpty) {
        final lessonIds = await (database.select(database.lessons)
              ..where((t) => t.unitId.isIn(unitIds)))
            .map((l) => l.id)
            .get();
        if (lessonIds.isNotEmpty) {
          await (database.delete(database.lessonContents)
                ..where((t) => t.lessonId.isIn(lessonIds)))
              .go();
        }
        await (database.delete(database.lessons)
              ..where((t) => t.unitId.isIn(unitIds)))
            .go();
      }
      await (database.delete(database.units)
            ..where((t) => t.sectionId.equals(sectionId)))
          .go();
      await (database.delete(database.sections)
            ..where((t) => t.id.equals(sectionId)))
          .go();
    });
  }

  /// Record a completed Anki deck import in the `anki_imports` table.
  @override
  Future<void> recordAnkiImport(db.AnkiImportsCompanion companion) async {
    await database.into(database.ankiImports).insertOnConflictUpdate(companion);
  }

  /// List all recorded Anki imports, most recent first.
  @override
  Future<List<db.AnkiImport>> ankiImports() async {
    final rows = await (database.select(database.ankiImports)
          ..orderBy([(t) => OrderingTerm.desc(t.importedAt)]))
        .get();
    return rows;
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
      type: _lessonTypeByName(row.type),
      template: _lessonTemplateByName(row.template),
      prerequisiteLessonIds: _decodeStringList(row.prerequisiteLessonIds),
      content: content,
    );
  }

  /// Resolve [LessonType] from a stored string without throwing. An unknown
  /// value (forward-incompatible content version, manual DB edit) degrades to
  /// [LessonType.normal], mirroring the `@Default(LessonType.normal)` fallback
  /// in `Lesson.fromJson` so the read path never crashes section()/lessonById().
  LessonType _lessonTypeByName(String name) {
    final resolved = enumByName(LessonType.values, name,
        fallback: LessonType.normal);
    if (resolved == LessonType.normal && name != LessonType.normal.name) {
      logger.w('Unknown LessonType "$name", falling back to normal');
    }
    return resolved;
  }

  /// Resolve [LessonTemplate] from a stored string without throwing. See
  /// [_lessonTypeByName]; falls back to [LessonTemplate.legacy].
  LessonTemplate _lessonTemplateByName(String name) {
    final resolved = enumByName(LessonTemplate.values, name,
        fallback: LessonTemplate.legacy);
    if (resolved == LessonTemplate.legacy && name != LessonTemplate.legacy.name) {
      logger.w('Unknown LessonTemplate "$name", falling back to legacy');
    }
    return resolved;
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