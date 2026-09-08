// Flutter imports:
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

// Package imports:
import 'package:drift/drift.dart';

// Project imports:
import 'package:turna/application/language_registry.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/course_validator.dart';
import 'package:turna/courses/language_manifest.dart';
import 'package:turna/data/course_database.dart' hide Section;
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/section.dart';

/// Seeds [CourseDatabase] from the bundled JSON assets.
///
/// The DB is a derived cache of `assets/courses/turkish/`. Content is stored
/// **normalized** — the seeder runs `parseSection` before writing the
/// `LessonContent` blob.
///
/// **Invariant:** skip only when `contentVersion` meta equals the asset
/// `index.json` version **and** at least one section row exists, or when the
/// language carries an `uninstalled:<code>` marker (user removed it). Any
/// other state triggers a full reseed. Recovery for content changes is: bump
/// `index.json` version (or wipe the course tree). Empty optional tables
/// (e.g. expressions when the asset list is `[]`) never force a reseed.
///
/// Every write path **clears course tables before INSERT** so residue cannot
/// cause primary-key conflicts on cold start.
class DatabaseSeeder {
  final CourseDatabase db;
  final AssetBundle? bundle;
  DatabaseSeeder(this.db, {this.bundle});

  static const String metaContentVersion = 'contentVersion';
  static String metaContentVersionFor(String languageCode) =>
      '$metaContentVersion:${LanguageCodes.canonicalize(languageCode)}';

  /// Marker written by [CourseRepository.deleteBuiltinLanguage] so cold-start
  /// seeding does not resurrect a language the user uninstalled. Cleared by
  /// the restore path before [seedLanguage] re-runs.
  static const String metaUninstalled = 'uninstalled';
  static String metaUninstalledFor(String languageCode) =>
      '$metaUninstalled:${LanguageCodes.canonicalize(languageCode)}';

  /// Seed or reseed from assets when needed. Returns `true` if the DB was
  /// written.
  ///
  /// Skip iff version matches and sections exist; otherwise clear + full seed.
  /// The content version is the composite of `index.json` and
  /// `expressions.json` versions (`"$indexVersion+$expressionsVersion"`), so
  /// bumping either triggers a reseed.
  Future<String> _loadAsset(String key) {
    return (bundle ?? rootBundle).loadString(key);
  }

  Future<String?> _tryLoadAsset(String key) async {
    try {
      return await _loadAsset(key);
    } catch (_) {
      return null;
    }
  }

  Future<bool> seedIfNeeded() async {
    await LanguageRegistry.instance.load(bundle: bundle);
    final languages = LanguageRegistry.instance.languages;
    var wrote = false;
    CourseLoader.invalidateCaches();
    for (final language in languages) {
      wrote = await _seedLanguageIfNeeded(language) || wrote;
    }
    CourseLoader.invalidateCaches();
    return wrote;
  }

  /// Force one language through the seed path (restore after uninstall).
  ///
  /// The caller is responsible for clearing the `uninstalled:<code>` marker
  /// first — [_seedLanguageIfNeeded] skips marked languages.
  Future<bool> seedLanguage(String languageCode) async {
    await LanguageRegistry.instance.load(bundle: bundle);
    final language = LanguageRegistry.instance.byCode(languageCode);
    if (language.code != LanguageCodes.canonicalize(languageCode)) {
      logger.w('Cannot seed unknown language $languageCode');
      return false;
    }
    CourseLoader.invalidateCaches();
    final wrote = await _seedLanguageIfNeeded(language);
    CourseLoader.invalidateCaches();
    return wrote;
  }

  Future<bool> _seedLanguageIfNeeded(LanguageDescriptor language) async {
    final uninstalled = await _readMeta(metaUninstalledFor(language.code));
    if (uninstalled != null) {
      return false;
    }
    final indexRaw = await _tryLoadAsset(CourseLoader.indexAssetFor(language.code));
    if (indexRaw == null) {
      logger.w(
        'Skipping seed for ${language.code}: missing '
        '${CourseLoader.indexAssetFor(language.code)}',
      );
      return false;
    }
    final index = jsonDecode(indexRaw) as Map<String, dynamic>;
    final indexLanguage = LanguageCodes.canonicalize(
      '${index['language'] ?? language.code}',
    );
    if (indexLanguage != language.code) {
      throw StateError(
        'Language manifest/index mismatch: manifest ${language.code} '
        'vs index.json $indexLanguage',
      );
    }
    final indexVersion = '${index['version'] ?? 0}';

    final expressionsRaw = await _tryLoadAsset(
      CourseLoader.expressionsAssetFor(language.code),
    );
    final expressionsVersion = expressionsRaw == null
        ? '0'
        : '${(jsonDecode(expressionsRaw) as Map<String, dynamic>)['version'] ?? 0}';
    final assetVersion = '$indexVersion+$expressionsVersion';

    var storedVersion = await _readMeta(metaContentVersionFor(language.code));
    if (language.code == LanguageCodes.turkish) {
      final legacy = await _readMeta(metaContentVersion);
      if (storedVersion == null) {
        storedVersion = legacy;
      } else if (legacy != null &&
          legacy != storedVersion &&
          legacy != assetVersion) {
        storedVersion = legacy;
      }
    }
    final existingSections = await (db.select(db.sections)
          ..where((t) => t.languageCode.equals(language.code))
          ..limit(1))
        .get();
    final hasSections = existingSections.isNotEmpty;

    if (storedVersion == assetVersion && hasSections) {
      return false;
    }

    if (storedVersion != null && storedVersion != assetVersion) {
      logger.i(
        'Course ${language.code} version $storedVersion → $assetVersion; reseeding',
      );
    } else if (storedVersion == assetVersion && !hasSections) {
      logger.i(
        'Course ${language.code} version $assetVersion matches but sections '
        'missing; reseeding',
      );
    } else {
      logger.i(
        'Course ${language.code} empty or unversioned; seeding $assetVersion',
      );
    }

    await _clearLanguageTables(language.code);
    await _seedLanguage(language, indexRaw: indexRaw, index: index);
    await _writeMeta(metaContentVersionFor(language.code), assetVersion);
    if (language.code == LanguageCodes.turkish) {
      await _writeMeta(metaContentVersion, assetVersion);
    }
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

  Future<void> _clearLanguageTables(String languageCode) async {
    final code = LanguageCodes.canonicalize(languageCode);
    await db.transaction(() async {
      await (db.delete(db.lessonContents)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (db.delete(db.lessons)..where((t) => t.languageCode.equals(code)))
          .go();
      await (db.delete(db.units)..where((t) => t.languageCode.equals(code)))
          .go();
      await (db.delete(db.sections)..where((t) => t.languageCode.equals(code)))
          .go();
      await (db.delete(db.vocabulary)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (db.delete(db.grammarPoints)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (db.delete(db.expressions)
            ..where((t) => t.languageCode.equals(code)))
          .go();
    });
  }

  Future<void> _seedLanguage(
    LanguageDescriptor language, {
    required String indexRaw,
    required Map<String, dynamic> index,
  }) async {
    await _seedSections(language, index: index);
    await _seedGrammarPoints(language);
    await _seedExpressions(language);
  }

  Future<void> _seedSections(
    LanguageDescriptor language, {
    required Map<String, dynamic> index,
  }) async {
    final entries = (index['sections'] as List).cast<Map<String, dynamic>>();
    final vocabRaw = await _loadAsset(CourseLoader.vocabAssetFor(language.code));
    final vocab = parseVocabulary(vocabRaw);
    final code = language.code;
    final baseDir = CourseLoader.baseDirFor(code);

    // Vocabulary first (independent of the section tree).
    await db.batch((b) {
      for (final w in vocab) {
        b.insert(
          db.vocabulary,
          VocabularyCompanion(
            id: Value(w.id),
            languageCode: Value(code),
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
      final raw = await _loadAsset('$baseDir/$file');
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
                languageCode: Value(code),
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
            await db.into(db.lessons).insert(
                  LessonsCompanion(
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
            await db.into(db.lessonContents).insert(
                  LessonContentsCompanion(
                    lessonId: Value(l.id),
                    languageCode: Value(code),
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

  Future<void> _seedGrammarPoints(LanguageDescriptor language) async {
    final raw = await _tryLoadAsset(
      CourseLoader.grammarPointsAssetFor(language.code),
    );
    if (raw == null) return;
    final points = parseGrammarPoints(raw);
    final code = language.code;

    await db.batch((b) {
      for (final gp in points) {
        b.insert(
          db.grammarPoints,
          GrammarPointsCompanion(
            id: Value(gp.id),
            languageCode: Value(code),
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

  Future<void> _seedExpressions(LanguageDescriptor language) async {
    final raw = await _tryLoadAsset(
      CourseLoader.expressionsAssetFor(language.code),
    );
    if (raw == null) return;
    final expressions = parseExpressions(raw);
    final code = language.code;

    await db.batch((b) {
      for (final e in expressions) {
        b.insert(
          db.expressions,
          ExpressionsCompanion(
            id: Value(e.id),
            languageCode: Value(code),
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
