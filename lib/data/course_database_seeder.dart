// Flutter imports:
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

// Package imports:
import 'package:drift/drift.dart';

// Project imports:
import 'package:turna/core/logger.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/course_validator.dart';
import 'package:turna/data/course_database.dart' hide Section;
import 'package:turna/domain/course/section.dart';

/// Seeds [CourseDatabase] from the bundled JSON assets.
///
/// The DB is a derived cache of `assets/courses/turkish/`. Content is stored
/// **normalized** — the seeder runs `parseSection` before writing the
/// `LessonContent` blob.
///
/// **Invariant:** skip only when `contentVersion` meta equals the asset
/// `index.json` version **and** at least one section row exists. Any other
/// state triggers a full reseed. Recovery for content changes is: bump
/// `index.json` version (or wipe the course tree). Empty optional tables
/// (e.g. expressions when the asset list is `[]`) never force a reseed.
///
/// Every write path **clears course tables before INSERT** so residue cannot
/// cause primary-key conflicts on cold start.
class DatabaseSeeder {
  final CourseDatabase db;
  DatabaseSeeder(this.db);

  static const String metaContentVersion = 'contentVersion';

  /// Seed or reseed from assets when needed. Returns `true` if the DB was
  /// written.
  ///
  /// Skip iff version matches and sections exist; otherwise clear + full seed.
  /// The content version is the composite of `index.json` and
  /// `expressions.json` versions (`"$indexVersion+$expressionsVersion"`), so
  /// bumping either triggers a reseed.
  Future<bool> seedIfNeeded() async {
    final indexRaw = await rootBundle.loadString(CourseLoader.indexAsset);
    final index = jsonDecode(indexRaw) as Map<String, dynamic>;
    final indexVersion = '${index['version'] ?? 0}';

    final expressionsRaw = await rootBundle.loadString(
      CourseLoader.expressionsAsset,
    );
    final expressionsJson = jsonDecode(expressionsRaw) as Map<String, dynamic>;
    final expressionsVersion = '${expressionsJson['version'] ?? 0}';
    final assetVersion = '$indexVersion+$expressionsVersion';

    final storedVersion = await _readMeta(metaContentVersion);
    final existingSections = await (db.select(db.sections)..limit(1)).get();
    final hasSections = existingSections.isNotEmpty;

    if (storedVersion == assetVersion && hasSections) {
      return false;
    }

    if (storedVersion != null && storedVersion != assetVersion) {
      logger.i(
        'Course content version $storedVersion → $assetVersion; reseeding',
      );
    } else if (storedVersion == assetVersion && !hasSections) {
      logger.i(
        'Course content version $assetVersion matches but sections missing; '
        'reseeding',
      );
    } else {
      logger.i('Course database empty or unversioned; seeding $assetVersion');
    }

    // Always wipe before plain INSERT — empty clear is cheap; residue is not.
    await _clearCourseTables();
    CourseLoader.invalidateCaches();

    await _seed(
      seedSections: true,
      seedGrammar: true,
      seedExpressions: true,
    );
    await _writeMeta(metaContentVersion, assetVersion);
    CourseLoader.invalidateCaches();
    return true;
  }

  /// Deprecated name: seeding is version-driven, not "if empty". Prefer
  /// [seedIfNeeded].
  @Deprecated('Use seedIfNeeded — policy is version + sections, not emptiness')
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
      // P5F-32: the reseed wipes sections/units/lessons, so a surviving
      // projection index/manifest would keep pointing at deleted trees and
      // the projection fingerprint no-op would never rebuild them. Dropping
      // both forces the next projectSource to republish.
      await db
          .customStatement('DELETE FROM official_anki_projection_index');
      await db
          .customStatement('DELETE FROM official_anki_projection_manifest');
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
    final indexRaw = await rootBundle.loadString(CourseLoader.indexAsset);
    final index = jsonDecode(indexRaw) as Map<String, dynamic>;
    final entries = (index['sections'] as List).cast<Map<String, dynamic>>();

    final vocabRaw = await rootBundle.loadString(CourseLoader.vocabAsset);
    final vocab = parseVocabulary(vocabRaw);

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

    // Stream per section: parse → cross-id check against running sets → write
    // → drop Freezed graph. Avoids holding all ~9300 lesson bodies in RAM.
    final seenUnitIds = <String>{};
    final seenLessonIds = <String>{};
    var sectionCount = 0;

    for (var sOrder = 0; sOrder < entries.length; sOrder++) {
      final entry = entries[sOrder];
      final file = entry['file'] as String;
      final raw = await rootBundle.loadString('${CourseLoader.baseDir}/$file');
      // parseSection runs _normalizeSection -> stored normalized.
      final section = parseSection(raw);

      final crossErrors = collectCrossCourseIdErrorsAgainst(
        section,
        seenUnitIds: seenUnitIds,
        seenLessonIds: seenLessonIds,
      );
      if (crossErrors.isNotEmpty) {
        for (final err in crossErrors) {
          logger.e(err);
        }
        throw CourseValidationException(crossErrors);
      }

      // Scale contract (same ceilings as course_validator).
      if (section.units.length > kMaxUnitsPerSection) {
        throw CourseValidationException([
          'Section ${section.id} has ${section.units.length} units '
              '(max $kMaxUnitsPerSection).',
        ]);
      }
      for (final u in section.units) {
        if (u.lessons.length > kMaxLessonsPerUnit) {
          throw CourseValidationException([
            'Unit ${u.id} has ${u.lessons.length} lessons '
                '(max $kMaxLessonsPerUnit).',
          ]);
        }
      }

      await db.transaction(() async {
        await db.into(db.sections).insert(
              SectionsCompanion(
                id: Value(section.id),
                name: Value(section.name),
                description: Value(section.description),
                level: Value(section.level ?? ''),
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
      sectionCount++;
      logger.i(
        'Seeded section ${section.id} '
        '(${section.units.length} units, order $sOrder)',
      );
    }

    logger.i('Seeded course database: $sectionCount sections, '
        '${vocab.length} vocab words');
  }

  /// Collects cross-course unit/lesson id uniqueness errors from the assembled
  /// [sections]. Runtime mirror of the CI-only `validateCourse`
  /// check — runtime `validateSection` only checks within a single section.
  ///
  /// Vocab / expression ids are not checked here (expressions asset is
  /// currently empty; vocab ids are validated per-section already).
  @visibleForTesting
  static List<String> collectCrossCourseIdErrors(Iterable<Section> sections) {
    final unitIds = <String>{};
    final lessonIds = <String>{};
    final errors = <String>[];
    for (final section in sections) {
      errors.addAll(
        collectCrossCourseIdErrorsAgainst(
          section,
          seenUnitIds: unitIds,
          seenLessonIds: lessonIds,
        ),
      );
    }
    return errors;
  }

  /// Streaming variant: merge [section] into running id sets; returns only
  /// new errors for this section. Mutates [seenUnitIds] / [seenLessonIds]
  /// on success paths for unique ids (duplicates are still recorded in the
  /// sets so later collisions continue to be detected).
  @visibleForTesting
  static List<String> collectCrossCourseIdErrorsAgainst(
    Section section, {
    required Set<String> seenUnitIds,
    required Set<String> seenLessonIds,
  }) {
    final errors = <String>[];
    for (final u in section.units) {
      if (u.id.isEmpty) continue;
      if (!seenUnitIds.add(u.id)) {
        errors.add('Duplicate unit id across course: ${u.id}');
      }
      for (final l in u.lessons) {
        if (l.id.isEmpty) continue;
        if (!seenLessonIds.add(l.id)) {
          errors.add('Duplicate lesson id across course: ${l.id}');
        }
      }
    }
    return errors;
  }

  Future<void> _seedGrammarPoints() async {
    final raw =
        await rootBundle.loadString(CourseLoader.grammarPointsAsset);
    final points = parseGrammarPoints(raw);

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
    final raw = await rootBundle.loadString(CourseLoader.expressionsAsset);
    final expressions = parseExpressions(raw);

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
