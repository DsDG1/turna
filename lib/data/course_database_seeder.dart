// Flutter imports:
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

// Package imports:
import 'package:drift/drift.dart';

// Project imports:
import 'package:words625/core/logger.dart';
import 'package:words625/courses/course_loader.dart';
import 'package:words625/data/course_database.dart';

/// Seeds [CourseDatabase] from the bundled JSON assets.
///
/// The DB is a derived cache of `assets/courses/swahili/`. Content is stored
/// **normalized** — the seeder runs `parseSwahiliSection` before writing the
/// `LessonContent` blob.
///
/// Reseed is driven by `index.json` `version` stored in [CourseMeta]. When the
/// asset version differs from the DB, course tables are wiped and re-imported.
class DatabaseSeeder {
  final CourseDatabase db;
  DatabaseSeeder(this.db);

  static const String metaContentVersion = 'contentVersion';

  /// Seed or reseed from assets when empty or when [index.json] version
  /// changes. Returns `true` if the DB was written.
  Future<bool> seedIfNeeded() async {
    final indexRaw = await rootBundle.loadString(SwahiliCourse.indexAsset);
    final index = jsonDecode(indexRaw) as Map<String, dynamic>;
    final assetVersion = '${index['version'] ?? 0}';

    final storedVersion = await _readMeta(metaContentVersion);
    final existingSections = await (db.select(db.sections)..limit(1)).get();
    final existingGrammar =
        await (db.select(db.grammarPoints)..limit(1)).get();
    final existingExpressions = await (db.select(db.expressions)..limit(1)).get();

    final empty = existingSections.isEmpty ||
        existingGrammar.isEmpty ||
        existingExpressions.isEmpty;
    final versionMismatch =
        storedVersion == null || storedVersion != assetVersion;

    if (!empty && !versionMismatch) {
      return false;
    }

    if (versionMismatch && !empty) {
      logger.i(
        'Course content version $storedVersion → $assetVersion; reseeding',
      );
      await _clearCourseTables();
      SwahiliCourse.invalidateCaches();
    }

    await _seed(
      seedSections: true,
      seedGrammar: true,
      seedExpressions: true,
    );
    await _writeMeta(metaContentVersion, assetVersion);
    SwahiliCourse.invalidateCaches();
    return true;
  }

  /// Back-compat alias for older call sites / tests.
  Future<bool> seedIfEmpty() => seedIfNeeded();

  Future<String?> _readMeta(String key) async {
    final row = await (db.select(db.courseMeta)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _writeMeta(String key, String value) async {
    await db.into(db.courseMeta).insertOnConflictUpdate(
          CourseMetaCompanion(
            key: Value(key),
            value: Value(value),
          ),
        );
  }

  Future<void> _clearCourseTables() async {
    await db.transaction(() async {
      await db.delete(db.lessonContents).go();
      await db.delete(db.lessons).go();
      await db.delete(db.units).go();
      await db.delete(db.sections).go();
      await db.delete(db.vocabulary).go();
      await db.delete(db.grammarPoints).go();
      await db.delete(db.expressions).go();
      // Keep courseMeta until we rewrite version after seed.
    });
  }

  Future<void> _seed({
    required bool seedSections,
    required bool seedGrammar,
    required bool seedExpressions,
  }) async {
    if (seedSections) {
      await _seedSections();
    }
    if (seedGrammar) {
      await _seedGrammarPoints();
    }
    if (seedExpressions) {
      await _seedExpressions();
    }
  }

  Future<void> _seedSections() async {
    final indexRaw = await rootBundle.loadString(SwahiliCourse.indexAsset);
    final index = jsonDecode(indexRaw) as Map<String, dynamic>;
    final entries = (index['sections'] as List).cast<Map<String, dynamic>>();

    final vocabRaw = await rootBundle.loadString(SwahiliCourse.vocabAsset);
    final vocab = parseSwahiliVocabulary(vocabRaw);

    // Vocabulary first (independent of the section tree).
    await db.batch((b) {
      for (final w in vocab) {
        b.insert(
          db.vocabulary,
          VocabularyCompanion(
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

    for (var sOrder = 0; sOrder < entries.length; sOrder++) {
      final entry = entries[sOrder];
      final file = entry['file'] as String;
      final raw = await rootBundle.loadString(
        '${SwahiliCourse.baseDir}/$file',
      );
      // parseSwahiliSection runs _normalizeSection -> stored normalized.
      final section = parseSwahiliSection(raw);

      await db.transaction(() async {
        await db.into(db.sections).insert(
              SectionsCompanion(
                id: Value(section.id),
                name: Value(section.name),
                description: Value(section.description),
                prerequisiteSectionIds:
                    Value(jsonEncode(section.prerequisiteSectionIds)),
                sortOrder: Value(sOrder),
              ),
            );

        for (var uOrder = 0; uOrder < section.units.length; uOrder++) {
          final u = section.units[uOrder];
          await db.into(db.units).insert(
                UnitsCompanion(
                  id: Value(u.id),
                  sectionId: Value(section.id),
                  name: Value(u.name),
                  description: Value(u.description),
                  prerequisiteUnitIds: Value(jsonEncode(u.prerequisiteUnitIds)),
                  sortOrder: Value(uOrder),
                ),
              );

          for (var lOrder = 0; lOrder < u.lessons.length; lOrder++) {
            final l = u.lessons[lOrder];
            await db.into(db.lessons).insert(
                  LessonsCompanion(
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
            await db.into(db.lessonContents).insert(
                  LessonContentsCompanion(
                    lessonId: Value(l.id),
                    contentJson: Value(jsonEncode(l.content.toJson())),
                  ),
                );
          }
        }
      });
    }

    logger.i('Seeded course database: ${entries.length} sections, '
        '${vocab.length} vocab words');
  }

  Future<void> _seedGrammarPoints() async {
    final raw =
        await rootBundle.loadString(SwahiliCourse.grammarPointsAsset);
    final points = parseSwahiliGrammarPoints(raw);

    await db.batch((b) {
      for (final gp in points) {
        b.insert(
          db.grammarPoints,
          GrammarPointsCompanion(
            id: Value(gp.id),
            title: Value(gp.title),
            explanation: Value(gp.explanation),
            exampleExpressionIds: Value(jsonEncode(gp.exampleExpressionIds)),
            exampleSentenceIds: Value(jsonEncode(gp.exampleSentenceIds)),
            practiceItems: Value(
              jsonEncode(gp.practiceItems.map((i) => i.toJson()).toList()),
            ),
          ),
        );
      }
    });

    logger.i('Seeded grammar points: ${points.length}');
  }

  Future<void> _seedExpressions() async {
    final raw = await rootBundle.loadString(SwahiliCourse.expressionsAsset);
    final expressions = parseSwahiliExpressions(raw);

    await db.batch((b) {
      for (final e in expressions) {
        b.insert(
          db.expressions,
          ExpressionsCompanion(
            id: Value(e.id),
            term: Value(e.term),
            translation: Value(e.translation),
            pronunciation: Value(e.pronunciation),
            audioAsset: Value(e.audioAsset),
            tags: Value(jsonEncode(e.tags)),
          ),
        );
      }
    });

    logger.i('Seeded expressions: ${expressions.length}');
  }
}
