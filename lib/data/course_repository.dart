// Flutter imports:
import 'dart:convert';
import 'dart:isolate';

// Package imports:
import 'package:drift/drift.dart' hide Expression;

// Project imports:
import 'package:turna/core/logger.dart';
import 'package:turna/core/utils.dart';
import 'package:turna/data/course_database.dart' as db;
import 'package:turna/data/course_database_seeder.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/domain/course/word_entry.dart';
import 'package:injectable/injectable.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';

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
  /// `units` empty) in on-disk order. The id tiebreak keeps the order
  /// deterministic when sort orders collide across writers.
  @override
  Future<List<Section>> sectionShells({String? languageCode}) async {
    final query = database.select(database.sections);
    if (languageCode != null) {
      query.where(
        (t) => t.languageCode.equals(LanguageCodes.canonicalize(languageCode)),
      );
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.sortOrder),
      (t) => OrderingTerm(expression: t.id),
    ]);
    final rows = await query.get();
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
  Future<List<WordEntry>> vocabulary({String? languageCode}) async {
    final query = database.select(database.vocabulary);
    if (languageCode != null) {
      query.where(
        (t) => t.languageCode.equals(LanguageCodes.canonicalize(languageCode)),
      );
    }
    final rows = await query.get();
    // crash-hunt PR1: after an official import this table holds one row per
    // card (tens of thousands on big decks) and the per-row tags jsonDecode
    // froze course reload on the UI isolate. Drift rows are plain data —
    // decode off-isolate once the list is big enough to matter.
    if (rows.length < 64) {
      return [for (final r in rows) _wordEntry(r)];
    }
    return Isolate.run(() => [for (final r in rows) _wordEntry(r)]);
  }

  /// All grammar points.
  @override
  Future<List<GrammarPoint>> grammarPoints({String? languageCode}) async {
    final query = database.select(database.grammarPoints);
    if (languageCode != null) {
      query.where(
        (t) => t.languageCode.equals(LanguageCodes.canonicalize(languageCode)),
      );
    }
    final rows = await query.get();
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
  Future<List<Expression>> expressions({String? languageCode}) async {
    final query = database.select(database.expressions);
    if (languageCode != null) {
      query.where(
        (t) => t.languageCode.equals(LanguageCodes.canonicalize(languageCode)),
      );
    }
    final rows = await query.get();
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
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) => OrderingTerm(expression: t.id),
          ]))
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
          OrderingTerm(expression: database.units.id),
          OrderingTerm(expression: database.lessons.sortOrder),
          OrderingTerm(expression: database.lessons.id),
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
    final contentJson = contentRow?.contentJson;
    // crash-hunt PR1: official projection lessons cap at 512KB of JSON —
    // decoding that on the UI isolate is a visible freeze on open. Small
    // bodies stay inline (isolate spawn costs more than the decode).
    if (contentJson == null || contentJson.length < 16 * 1024) {
      return _toLesson(row, contentJson);
    }
    return Isolate.run(() => _toLesson(row, contentJson));
  }

  /// Full lesson bodies whose content JSON contains any of [needles].
  ///
  /// Used by Anki review to resolve <=20 due word ids without loading every
  /// lesson in a 5k-card deck (retired Legacy assembler-era concern).
  ///
  /// [needles] are Anki word ids (`anki-<importId>-c<cardId>`, card-level per
  /// decision 2). Each needle is anchored with the interaction-id ord
  /// separator `-c` before LIKE matching: Anki interaction ids are
  /// `${wordId}-c${ord}`, so `${wordId}-c` is always a substring of a lesson
  /// body that contains that card. Anchoring prevents prefix collisions
  /// (`anki-imp-c45` would otherwise also match `anki-imp-c450`). Note: the
  /// `importId` segment contains `_` (a SQL LIKE wildcard), which can only
  /// widen a match to a non-existent id, never drop a real one.
  @override
  Future<List<Lesson>> lessonsContainingAny(Iterable<String> needles) async {
    final list = [
      for (final n in needles)
        if (n.isNotEmpty) n,
    ];
    if (list.isEmpty) return const <Lesson>[];

    // Note: drift.Expression is hidden in this file (collides with the domain
    // Expression model) - use type inference for the OR-chain of LIKEs.
    // Each needle is suffixed with `-c` (the ord separator) so a card id that
    // is a prefix of another (e.g. c45 vs c450) does not load the wrong lesson.
    final contentQuery = database.select(database.lessonContents)
      ..where((t) {
        var expr = t.contentJson.like('%${list.first}-c%');
        for (var i = 1; i < list.length; i++) {
          expr = expr | t.contentJson.like('%${list[i]}-c%');
        }
        return expr;
      });
    final contentRows = await contentQuery.get();
    if (contentRows.isEmpty) return const <Lesson>[];

    final contentByLessonId = {
      for (final r in contentRows) r.lessonId: r.contentJson,
    };
    final lessonIds = contentByLessonId.keys.toList();
    final lessonRows = await (database.select(database.lessons)
          ..where((t) => t.id.isIn(lessonIds)))
        .get();

    // crash-hunt PR1: review due-resolution decodes every matching lesson
    // body (≤512KB each) — on big decks that was seconds of UI-isolate JSON
    // decode. Rows and bodies are plain data; decode them off-isolate.
    return Isolate.run(() {
      return [
        for (final lr in lessonRows)
          _toLesson(lr, contentByLessonId[lr.id]),
      ];
    });
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
  ///
  /// Uses Drift [batch] so a multi-hundred-lesson Anki section is one
  /// prepared statement stream instead of thousands of awaited round-trips.
  @override
  Future<void> bulkInsertCourseTree(Section section) async {
    // Wrap the MAX-read + batch-write in a transaction so a concurrent
    // reader cannot see a half-built tree (new section row but no units/
    // lessons yet) and so two imports racing on the same `nextOrder` see a
    // consistent MAX(sort_order) value. Without the transaction, each
    // import reads the same pre-write MAX and writes the same nextOrder
    // — there is no UNIQUE constraint on sort_order, so the L1 tree's
    // ordering would flicker between launches.
    await database.transaction(() async {
      final maxRow = await database
          .customSelect(
            'SELECT MAX(sort_order) AS m FROM sections',
            readsFrom: {database.sections},
          )
          .getSingleOrNull();
      final maxOrder = maxRow?.read<int?>('m');
      final nextOrder = (maxOrder ?? -1) + 1;

      // Pre-encode JSON off the insert hot path (still main isolate, but once
      // per lesson rather than interleaved with SQLite awaits).
      final sectionCompanion = db.SectionsCompanion(
        id: Value(section.id),
        languageCode: Value(section.level == 'Anki' ||
                section.level == 'OfficialAnki'
            ? 'anki'
            : LanguageCodes.turkish),
        name: Value(section.name),
        description: Value(section.description),
        level: Value(section.level ?? ''),
        prerequisiteSectionIds:
            Value(jsonEncode(section.prerequisiteSectionIds)),
        sortOrder: Value(nextOrder),
      );

      final unitCompanions = <db.UnitsCompanion>[];
      final lessonCompanions = <db.LessonsCompanion>[];
      final contentCompanions = <db.LessonContentsCompanion>[];

      for (var uOrder = 0; uOrder < section.units.length; uOrder++) {
        final u = section.units[uOrder];
        unitCompanions.add(db.UnitsCompanion(
          id: Value(u.id),
          languageCode: Value(section.level == 'Anki' ||
                  section.level == 'OfficialAnki'
              ? 'anki'
              : LanguageCodes.turkish),
          sectionId: Value(section.id),
          name: Value(u.name),
          description: Value(u.description),
          prerequisiteUnitIds: Value(jsonEncode(u.prerequisiteUnitIds)),
          sortOrder: Value(uOrder),
        ));
        for (var lOrder = 0; lOrder < u.lessons.length; lOrder++) {
          final l = u.lessons[lOrder];
          lessonCompanions.add(db.LessonsCompanion(
            id: Value(l.id),
            languageCode: Value(section.level == 'Anki' ||
                    section.level == 'OfficialAnki'
                ? 'anki'
                : LanguageCodes.turkish),
            unitId: Value(u.id),
            name: Value(l.name),
            description: Value(l.description),
            type: Value(l.type.name),
            template: Value(l.template.name),
            prerequisiteLessonIds: Value(jsonEncode(l.prerequisiteLessonIds)),
            sortOrder: Value(lOrder),
          ));
          contentCompanions.add(db.LessonContentsCompanion(
            lessonId: Value(l.id),
            languageCode: Value(section.level == 'Anki' ||
                    section.level == 'OfficialAnki'
                ? 'anki'
                : LanguageCodes.turkish),
            contentJson: Value(jsonEncode(l.content.toJson())),
          ));
        }
      }

      await database.batch((b) {
        b.insert(
          database.sections,
          sectionCompanion,
          // DoNothing on id collision: a previous import already owns this
          // section id. Letting DoUpdate clobber the existing section's
          // name/level would leave the first import's vocab rows (tagged
          // anki:<firstImportId>) looking orphaned; DoNothing makes the
          // importer's import-uniqueness check the only authoritative
          // gate, so callers must catch a same-id collision before
          // reaching this path.
          onConflict: DoNothing(),
        );
        for (final u in unitCompanions) {
          b.insert(database.units, u, onConflict: DoUpdate((_) => u));
        }
        for (final l in lessonCompanions) {
          b.insert(database.lessons, l, onConflict: DoUpdate((_) => l));
        }
        for (final c in contentCompanions) {
          b.insert(
            database.lessonContents,
            c,
            onConflict: DoUpdate((_) => c),
          );
        }
      });
    });
  }

  /// Bulk-upsert vocabulary entries (Anki importer). Single [batch] write.
  @override
  Future<void> bulkInsertVocabulary(List<WordEntry> words) async {
    if (words.isEmpty) return;
    final companions = [
      for (final w in words)
        db.VocabularyCompanion(
          id: Value(w.id),
          languageCode: const Value('anki'),
          term: Value(w.term),
          translation: Value(w.translation),
          pronunciation: Value(w.pronunciation),
          audioAsset: Value(w.audioAsset),
          tags: Value(jsonEncode(w.tags)),
        ),
    ];
    await database.batch((b) {
      for (final c in companions) {
        b.insert(database.vocabulary, c, onConflict: DoUpdate((_) => c));
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
  /// Delete one packed builtin language (content + SRS + history + mistakes).
  Future<void> deleteBuiltinLanguage(String languageCode) async {
    final code = LanguageCodes.canonicalize(languageCode);
    await database.transaction(() async {
      await (database.delete(database.lessonContents)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (database.delete(database.lessons)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (database.delete(database.units)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (database.delete(database.sections)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (database.delete(database.vocabulary)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (database.delete(database.grammarPoints)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (database.delete(database.expressions)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (database.delete(database.srsStates)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (database.delete(database.reviewEvents)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (database.delete(database.mistakes)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (database.delete(database.mistakeAggregates)
            ..where((t) => t.languageCode.equals(code)))
          .go();
      await (database.delete(database.courseMeta)
            ..where((t) =>
                t.key.equals(DatabaseSeeder.metaContentVersionFor(code))))
          .go();
      // Turkish also maintained the legacy unsuffixed key until schema v25;
      // leave no stale version behind for the next reseed decision.
      if (code == LanguageCodes.turkish) {
        await (database.delete(database.courseMeta)
              ..where((t) => t.key.equals(DatabaseSeeder.metaContentVersion)))
            .go();
      }
      // The marker (not the version wipe) is what stops cold-start seeding
      // from resurrecting this language.
      await database.into(database.courseMeta).insertOnConflictUpdate(
            db.CourseMetaCompanion(
              key: Value(DatabaseSeeder.metaUninstalledFor(code)),
              value: const Value('1'),
            ),
          );
    });
  }

  /// Remove the uninstall marker so the language can be reseeded again.
  Future<void> clearLanguageUninstallMarker(String languageCode) async {
    final code = LanguageCodes.canonicalize(languageCode);
    await (database.delete(database.courseMeta)
          ..where((t) => t.key.equals(DatabaseSeeder.metaUninstalledFor(code))))
        .go();
  }

  /// Language codes carrying an `uninstalled:<code>` marker.
  Future<Set<String>> uninstalledLanguageCodes() async {
    const prefix = '${DatabaseSeeder.metaUninstalled}:';
    final rows = await (database.select(database.courseMeta)
          ..where((t) => t.key.like('$prefix%')))
        .get();
    return rows
        .map((row) => row.key.substring(prefix.length))
        .where((code) => code.isNotEmpty)
        .toSet();
  }

  /// Content item count (vocabulary + grammar points + expressions) per
  /// builtin language — the "cards" figure shown in the uninstall
  /// confirmation.
  Future<Map<String, int>> builtinCardCounts() async {
    final rows = await database.customSelect(
      'SELECT language_code AS code, COUNT(*) AS n FROM ('
      'SELECT language_code FROM vocabulary '
      'UNION ALL SELECT language_code FROM grammar_points '
      'UNION ALL SELECT language_code FROM expressions'
      ') GROUP BY language_code',
      readsFrom: {
        database.vocabulary,
        database.grammarPoints,
        database.expressions,
      },
    ).get();
    return {
      for (final row in rows)
        LanguageCodes.canonicalize(row.read<String>('code')):
            row.read<int>('n'),
    };
  }

  Future<String?> contentVersion({String? languageCode}) async {
    final keys = [
      if (languageCode != null)
        DatabaseSeeder.metaContentVersionFor(languageCode),
      DatabaseSeeder.metaContentVersion,
    ];
    for (final key in keys) {
      final row = await (database.select(database.courseMeta)
            ..where((t) => t.key.equals(key)))
          .getSingleOrNull();
      if (row != null) return row.value;
    }
    return null;
  }

  /// Static + pure so Isolate.run closures can call it without capturing
  /// `this` (the repository holds the drift database handle). The app
  /// logger is console-only and safe to use from any isolate.
  static WordEntry _wordEntry(db.VocabularyData row) {
    return WordEntry(
      id: row.id,
      term: row.term,
      translation: row.translation,
      pronunciation: row.pronunciation,
      audioAsset: row.audioAsset,
      tags: _decodeStringList(row.tags),
    );
  }

  /// Static for the same off-isolate reason as [_wordEntry]; see
  /// [lessonById] / [lessonsContainingAny].
  static Lesson _toLesson(db.Lesson row, String? contentJson) {
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
  static LessonType _lessonTypeByName(String name) {
    final resolved = enumByName(LessonType.values, name,
        fallback: LessonType.normal);
    if (resolved == LessonType.normal && name != LessonType.normal.name) {
      logger.w('Unknown LessonType "$name", falling back to normal');
    }
    return resolved;
  }

  /// Resolve [LessonTemplate] from a stored string without throwing. See
  /// [_lessonTypeByName]; falls back to [LessonTemplate.legacy].
  static LessonTemplate _lessonTemplateByName(String name) {
    final resolved = enumByName(LessonTemplate.values, name,
        fallback: LessonTemplate.legacy);
    if (resolved == LessonTemplate.legacy && name != LessonTemplate.legacy.name) {
      logger.w('Unknown LessonTemplate "$name", falling back to legacy');
    }
    return resolved;
  }

  @override
  Future<void> deleteOfficialProjection(String sourceId) async {}

  static List<String> _decodeStringList(String encoded) {
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