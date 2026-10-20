// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:drift/drift.dart' show Value;
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/ai/ai_resource_consistency.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/data/course_database.dart' as db;
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/section.dart';

/// Persistence helpers for course-shaped JSON produced by importers and the
/// AI practice pipeline.
///
/// Generation itself lives in `application/ai/practice/` (phased outline →
/// lesson fill). This provider only writes a validated section tree into
/// `course.db` (and refreshes the loader caches) — the job-queue/library path
/// deliberately does **not** call it, because generated drafts stay outside the
/// course tree until the learner asks for them.
@lazySingleton
class AiCourseProvider extends ChangeNotifier {
  AiCourseProvider();

  /// Persists an arbitrary section JSON (e.g. from textbook import) into the
  /// DB after normalization and validation. Used by importers that already
  /// hold parsed JSON.
  Future<void> saveSectionJson(Map<String, dynamic> parsed) async {
    normalizeResources(parsed);
    autoFixResources(parsed);
    checkResourceSelfConsistency(parsed);
    final section = Section.fromJson(_normalizeForSave(parsed));
    await _writeSectionToDb(section, parsed);
    CourseLoader.invalidateCaches();
  }

  /// Updates a single existing lesson and its content in the DB.
  ///
  /// Not wired to any surface today (the in-lesson AI editor is gone); kept as
  /// the single validated write path for a future editor so lesson edits never
  /// grow a second DB writer. The caller is responsible for validating
  /// [lesson].
  Future<void> updateLessonInDb(Lesson lesson) async {
    final database = getIt<db.CourseDatabase>();

    // Preserve existing unit/sort metadata by reading the current lesson row.
    final existing = await (database.select(database.lessons)
          ..where((t) => t.id.equals(lesson.id)))
        .getSingleOrNull();
    if (existing == null) {
      throw StateError('Lesson ${lesson.id} not found in database.');
    }

    await database.transaction(() async {
      await database.into(database.lessons).insertOnConflictUpdate(
            db.LessonsCompanion(
              id: Value(lesson.id),
              // Carry the row's own language: the table's PK is
              // (language_code, id), so omitting it would upsert under the
              // 'tr' default and fork a duplicate row instead of updating
              // the existing one.
              languageCode: Value(existing.languageCode),
              unitId: Value(existing.unitId),
              name: Value(lesson.name),
              description: Value(lesson.description),
              type: Value(lesson.type.name),
              template: Value(lesson.template.name),
              prerequisiteLessonIds:
                  Value(jsonEncode(lesson.prerequisiteLessonIds)),
              sortOrder: Value(existing.sortOrder),
            ),
          );
      await database.into(database.lessonContents).insertOnConflictUpdate(
            db.LessonContentsCompanion(
              lessonId: Value(lesson.id),
              languageCode: Value(existing.languageCode),
              contentJson: Value(jsonEncode(lesson.content.toJson())),
            ),
          );
    });
    CourseLoader.invalidateCaches();
  }

  // --- DB write ---

  Future<void> _writeSectionToDb(
    Section section,
    Map<String, dynamic> parsed,
  ) async {
    final database = getIt<db.CourseDatabase>();
    final nextOrder = await _nextSectionSortOrder(database);
    // Tag every row with the owning language: the payload's `language` field
    // wins (importers can set it explicitly); otherwise the active practice
    // language. Without this the column default 'tr' would silently file
    // non-Turkish content under the Turkish course.
    final code = LanguageCodes.canonicalize(
      '${parsed['language'] ?? LanguageContentStore.activeCode}',
    );
    await _assertNoCrossLanguageIdCollision(database, section, code);

    await database.transaction(() async {
      await database.into(database.sections).insertOnConflictUpdate(
            db.SectionsCompanion(
              id: Value(section.id),
              languageCode: Value(code),
              name: Value(section.name),
              description: Value(section.description),
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
                languageCode: Value(code),
                sectionId: Value(section.id),
                name: Value(u.name),
                description: Value(u.description),
                prerequisiteUnitIds: Value(jsonEncode(u.prerequisiteUnitIds)),
                sortOrder: Value(uOrder),
              ),
            );
        for (var lOrder = 0; lOrder < u.lessons.length; lOrder++) {
          final l = u.lessons[lOrder];
          await database.into(database.lessons).insertOnConflictUpdate(
                db.LessonsCompanion(
                  id: Value(l.id),
                  languageCode: Value(code),
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
                  languageCode: Value(code),
                  contentJson: Value(jsonEncode(l.content.toJson())),
                ),
              );
        }
      }

      // Top-level resources: words / expressions / grammar points.
      await _writeResources(database, parsed, code);
    });
  }

  /// Runtime reads look rows up by bare id (`section(id)` / `lessonById(id)`
  /// / `sectionIdForUnit`), so the same id under two languages would throw
  /// downstream. Reject the write up front with a clear error instead.
  Future<void> _assertNoCrossLanguageIdCollision(
    db.CourseDatabase database,
    Section section,
    String code,
  ) async {
    Future<String?> otherLanguageOf(
      List<String> rowLanguages,
    ) =>
        Future.value(
          rowLanguages.where((c) => c != code).firstOrNull,
        );
    Future<void> check(String table, String id, Future<String?> other) async {
      final owner = await other;
      if (owner != null) {
        throw StateError(
          'Cannot save AI course into language "$code": $table id "$id" is '
          'already used by language "$owner" (ids must be unique across '
          'languages — runtime lookups are by bare id).',
        );
      }
    }

    await check(
      'section',
      section.id,
      otherLanguageOf(
        await (database.select(database.sections)
              ..where((t) => t.id.equals(section.id)))
            .map((r) => r.languageCode)
            .get(),
      ),
    );
    for (final unit in section.units) {
      await check(
        'unit',
        unit.id,
        otherLanguageOf(
          await (database.select(database.units)
                ..where((t) => t.id.equals(unit.id)))
              .map((r) => r.languageCode)
              .get(),
        ),
      );
      for (final lesson in unit.lessons) {
        await check(
          'lesson',
          lesson.id,
          otherLanguageOf(
            await (database.select(database.lessons)
                  ..where((t) => t.id.equals(lesson.id)))
                .map((r) => r.languageCode)
                .get(),
          ),
        );
      }
    }
  }

  Future<void> _writeResources(
    db.CourseDatabase database,
    Map<String, dynamic> parsed,
    String code,
  ) async {
    final words = (parsed['words'] as List?) ?? const [];
    for (final w in words) {
      if (w is! Map) continue;
      await database.into(database.vocabulary).insertOnConflictUpdate(
            db.VocabularyCompanion(
              id: Value(w['id']?.toString() ?? ''),
              languageCode: Value(code),
              term: Value(w['term']?.toString() ?? ''),
              translation: Value(w['translation']?.toString() ?? ''),
              pronunciation: Value(w['pronunciation']?.toString()),
              audioAsset: Value(w['audioAsset']?.toString()),
              tags: Value(jsonEncode(w['tags'] ?? const [])),
            ),
          );
    }
    final exprs = (parsed['expressions'] as List?) ?? const [];
    for (final e in exprs) {
      if (e is! Map) continue;
      await database.into(database.expressions).insertOnConflictUpdate(
            db.ExpressionsCompanion(
              id: Value(e['id']?.toString() ?? ''),
              languageCode: Value(code),
              term: Value(e['term']?.toString() ?? ''),
              translation: Value(e['translation']?.toString() ?? ''),
              pronunciation: Value(e['pronunciation']?.toString()),
              audioAsset: Value(e['audioAsset']?.toString()),
              tags: Value(jsonEncode(e['tags'] ?? const [])),
            ),
          );
    }
    final gps = (parsed['grammarPoints'] as List?) ?? const [];
    for (final g in gps) {
      if (g is! Map) continue;
      await database.into(database.grammarPoints).insertOnConflictUpdate(
            db.GrammarPointsCompanion(
              id: Value(g['id']?.toString() ?? ''),
              languageCode: Value(code),
              title: Value(g['title']?.toString() ?? ''),
              explanation: Value(g['explanation']?.toString() ?? ''),
              exampleExpressionIds:
                  Value(jsonEncode(g['exampleExpressionIds'] ?? const [])),
              exampleSentenceIds:
                  Value(jsonEncode(g['exampleSentenceIds'] ?? const [])),
              practiceItems: Value(jsonEncode(g['practiceItems'] ?? const [])),
            ),
          );
    }
  }

  Future<int> _nextSectionSortOrder(db.CourseDatabase database) async {
    final rows = await database.select(database.sections).get();
    if (rows.isEmpty) return 0;
    return rows.map((r) => r.sortOrder).fold<int>(0, (a, b) => a > b ? a : b) +
        1;
  }

  /// Minimal normalization mirroring [CourseLoader._normalizeLesson]:
  /// supports flat `content.questions` by wrapping them in one stage.
  Map<String, dynamic> _normalizeForSave(Map<String, dynamic> section) {
    final units = section['units'] as List<dynamic>?;
    if (units == null) return section;
    section['units'] = [
      for (final u in units) _normalizeUnitJson(u as Map<String, dynamic>),
    ];
    return section;
  }

  Map<String, dynamic> _normalizeUnitJson(Map<String, dynamic> unit) {
    final lessons = unit['lessons'] as List<dynamic>?;
    if (lessons == null) return unit;
    unit['lessons'] = [
      for (final l in lessons) _normalizeLessonJson(l as Map<String, dynamic>),
    ];
    return unit;
  }

  Map<String, dynamic> _normalizeLessonJson(Map<String, dynamic> lesson) {
    final content = lesson['content'] as Map<String, dynamic>?;
    if (content == null || !content.containsKey('questions')) {
      return lesson;
    }
    final questions = content['questions'] as List<dynamic>;
    content['stages'] = [
      {
        'id': 'stage-default',
        'name': (lesson['name'] as String?) ?? 'Practice',
        'items': questions,
      },
    ];
    content.remove('questions');
    return lesson;
  }
}
