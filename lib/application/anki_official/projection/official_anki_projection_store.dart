import 'package:drift/drift.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_canonical.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/courses/course_validator.dart'
    show kMaxLessonsPerUnit, kMaxUnitsPerSection;
import 'package:turna/data/course_database.dart'
    hide Section, Unit, Lesson, LessonContent;

class OfficialProjectionSummary {
  const OfficialProjectionSummary({
    required this.sourceId,
    required this.sectionIds,
    required this.itemCount,
    this.lessonCount = 0,
  });

  final String sourceId;
  final Set<String> sectionIds;
  final int itemCount;
  final int lessonCount;
}

/// One row of `official_anki_projection_index` (P5F-22 placement anchoring).
class OfficialAnkiProjectionIndexRow {
  const OfficialAnkiProjectionIndexRow({
    required this.cardId,
    required this.wordId,
    required this.sourceId,
    required this.sectionId,
    required this.unitId,
    required this.lessonId,
    required this.kind,
  });

  final int cardId;
  final String wordId;
  final String sourceId;
  final String sectionId;
  final String unitId;
  final String lessonId;
  final String kind;
}

/// Source-level CourseDatabase writes for official projection trees.
///
/// First ship is a full atomic rebuild, not an incremental patch.
class OfficialAnkiCourseProjectionStore {
  OfficialAnkiCourseProjectionStore(this.course);

  final CourseDatabase course;

  /// Test-only: throw after this many successful statements inside publish.
  int? debugFaultAfterStatements;

  Future<OfficialProjectionSummary> readOfficialProjectionSummary(
    String sourceId,
  ) async {
    final rows = await course.customSelect(
      'SELECT section_id FROM official_anki_projection_index WHERE source_id = ?',
      variables: [Variable(sourceId)],
    ).get();
    final manifest = await course.customSelect(
      'SELECT lesson_count FROM official_anki_projection_manifest '
      'WHERE source_id = ?',
      variables: [Variable(sourceId)],
    ).get();
    return OfficialProjectionSummary(
      sourceId: sourceId,
      sectionIds: {
        for (final row in rows) row.read<String>('section_id'),
      },
      itemCount: rows.length,
      lessonCount: manifest.isEmpty
          ? 0
          : manifest.single.read<int>('lesson_count'),
    );
  }

  Future<void> replaceOfficialProjection({
    required String sourceId,
    required OfficialAnkiProjectionPlan plan,
    String sourceFingerprint = '',
    int projectionVersion = 1,
    int publishedAtMillis = 0,
    Set<int> studiedCardIds = const {},
  }) async {
    await course.transaction(() async {
      _assertPlanWithinLimits(plan.items);
      // P0: re-publish keeps this source's tree position; a first publish
      // appends after every existing section. The compaction at the end of
      // the transaction turns the baseline into a collision-free dense order.
      final sectionBaseline = await _nextSectionSortOrderBaseline(sourceId);
      // P5F-33: drop the previous projection's vocabulary rows before the
      // index goes away (word ids are profile-scoped, so this index-driven
      // delete is the only precise way to clean this source's rows).
      await course.customStatement(
        'DELETE FROM vocabulary WHERE id IN '
        '(SELECT word_id FROM official_anki_projection_index '
        ' WHERE source_id = ?)',
        [sourceId],
      );
      await _deleteOwnedTree(sourceId);
      await course.customStatement(
        'DELETE FROM official_anki_projection_index WHERE source_id = ?',
        [sourceId],
      );
      var statements = 2;
      void tick() {
        final fault = debugFaultAfterStatements;
        if (fault != null && statements >= fault) {
          throw StateError('injected mid-publish fault after $statements');
        }
      }

      tick();
      final sections = <String, OfficialAnkiProjectedItem>{};
      final units = <String, OfficialAnkiProjectedItem>{};
      final lessons = <String, List<OfficialAnkiProjectedItem>>{};
      for (final item in plan.items) {
        _assertOwned(sourceId, item.sectionId);
        _assertOwned(sourceId, item.unitId);
        _assertOwned(sourceId, item.lessonId);
        sections.putIfAbsent(item.sectionId, () => item);
        units.putIfAbsent(item.unitId, () => item);
        lessons
            .putIfAbsent(item.lessonId, () => <OfficialAnkiProjectedItem>[])
            .add(item);
      }
      var sectionOrder = sectionBaseline;
      for (final section in sections.values) {
        await course.into(course.sections).insert(
              SectionsCompanion.insert(
                id: section.sectionId,
                name: section.sectionName,
                level: const Value('OfficialAnki'),
                sortOrder: Value(sectionOrder++),
              ),
            );
        statements++;
        tick();
      }
      var lastSectionId = '';
      var unitOrder = 0;
      for (final unit in units.values) {
        if (unit.sectionId != lastSectionId) {
          lastSectionId = unit.sectionId;
          unitOrder = 0;
        }
        await course.into(course.units).insert(
              UnitsCompanion.insert(
                id: unit.unitId,
                sectionId: unit.sectionId,
                name: unit.unitName,
                sortOrder: Value(unitOrder++),
              ),
            );
        statements++;
        tick();
      }
      var lastUnitId = '';
      var lessonOrder = 0;
      for (final entry in lessons.entries) {
        final first = entry.value.first;
        if (first.unitId != lastUnitId) {
          lastUnitId = first.unitId;
          lessonOrder = 0;
        }
        await course.into(course.lessons).insert(
              LessonsCompanion.insert(
                id: entry.key,
                unitId: first.unitId,
                name: first.lessonName,
                type: const Value('normal'),
                template: const Value('legacy'),
                sortOrder: Value(lessonOrder++),
              ),
            );
        statements++;
        tick();
        await course.into(course.lessonContents).insert(
              LessonContentsCompanion.insert(
                lessonId: entry.key,
                contentJson: officialAnkiLessonJson(entry.value),
              ),
            );
        statements++;
        tick();
      }
      // Doc 38 P5: multi-row inserts in ≤200-row blocks instead of 1–2
      // awaited statements per card (O(cards) was the dominant publish cost;
      // 200×9 columns stays far under SQLite's 32766-variable ceiling).
      const insertChunk = 200;
      String indexFingerprintFor(String itemFingerprint) =>
          sourceFingerprint.isEmpty ? itemFingerprint : sourceFingerprint;
      for (var start = 0; start < plan.items.length; start += insertChunk) {
        final chunk = plan.items.skip(start).take(insertChunk).toList();
        final values = List.filled(
          chunk.length,
          '(?, ?, ?, ?, ?, ?, ?, ?, 1)',
        ).join(',');
        await course.customStatement(
          'INSERT INTO official_anki_projection_index '
          '(source_id, card_id, word_id, section_id, unit_id, lesson_id, '
          'projection_kind, source_fingerprint, projection_version) '
          'VALUES $values',
          [
            for (final item in chunk)
              ...[
                sourceId,
                item.cardId,
                item.wordId,
                item.sectionId,
                item.unitId,
                item.lessonId,
                item.kind.name,
                indexFingerprintFor(item.sourceFingerprint),
              ],
          ],
        );
        statements++;
        tick();
      }
      // P5F-33 controlled vocabulary channel: one row per card, tagged
      // `official:<sourceId>`; built-in and legacy rows are never touched
      // because ids are the official word ids and deletes are index-driven.
      final vocabItems = [
        for (final item in plan.items)
          if (item.vocabulary != null) item,
      ];
      for (var start = 0; start < vocabItems.length; start += insertChunk) {
        final chunk = vocabItems.skip(start).take(insertChunk).toList();
        final values = List.filled(
          chunk.length,
          "(?, ?, ?, ?, ?, '[\"official:$sourceId\"]')",
        ).join(',');
        await course.customStatement(
          'INSERT OR REPLACE INTO vocabulary '
          '(id, term, translation, pronunciation, audio_asset, tags) '
          'VALUES $values',
          [
            for (final item in chunk)
              ...[
                item.wordId,
                item.vocabulary!.term,
                item.vocabulary!.translation,
                item.vocabulary!.pronunciation,
                item.vocabulary!.audioAsset,
              ],
          ],
        );
        statements++;
        tick();
      }
      await course.customStatement(
        'DELETE FROM official_anki_projection_manifest WHERE source_id = ?',
        [sourceId],
      );
      statements++;
      tick();
      await course.customStatement(
        'INSERT INTO official_anki_projection_manifest ('
        'source_id, active_generation, source_fingerprint, projection_version, '
        'section_count, lesson_count, item_count, published_at_millis'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          sourceId,
          sourceFingerprint.isEmpty
              ? 'gen-$publishedAtMillis'
              : sourceFingerprint,
          sourceFingerprint,
          projectionVersion,
          sections.length,
          lessons.length,
          plan.items.length,
          publishedAtMillis,
        ],
      );
      await _compactSectionSortOrders();
    });
    await CardIntroductionStore.resolve().seedOfficialProjection(
      sourceId: sourceId,
      cardIds: {for (final item in plan.items) item.cardId},
      studiedCardIds: studiedCardIds,
    );
  }

  /// Re-publish keeps the source's tree position (its previous sections'
  /// minimum sort order); a first publish appends after every existing
  /// section. Both read before any delete so the old rows still exist.
  Future<int> _nextSectionSortOrderBaseline(String sourceId) async {
    final owned = await course.customSelect(
      'SELECT MIN(s.sort_order) AS m FROM sections s WHERE s.id IN '
      '(SELECT DISTINCT section_id FROM official_anki_projection_index '
      ' WHERE source_id = ?)',
      variables: [Variable(sourceId)],
    ).get();
    final existing = owned.single.readNullable<int>('m');
    if (existing != null) return existing;
    final tail = await course.customSelect(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next FROM sections',
    ).get();
    return tail.single.read<int>('next');
  }

  /// Rewrites every section's sort order to a dense 0..n-1 sequence ordered
  /// by (sort_order, id). Heals collisions — publishes before the baseline
  /// fix started each source at 0 — and keeps read-side ordering stable even
  /// if another writer reintroduces ties.
  Future<void> _compactSectionSortOrders() async {
    final rows = await course.customSelect(
      'SELECT id, sort_order FROM sections ORDER BY sort_order, id',
    ).get();
    var order = 0;
    for (final row in rows) {
      final current = row.read<int>('sort_order');
      if (current == order) {
        order++;
        continue;
      }
      await course.customUpdate(
        'UPDATE sections SET sort_order = ? WHERE id = ?',
        variables: [Variable(order++), Variable(row.read<String>('id'))],
      );
    }
  }

  /// The projector packs oversized groups, so a violation here means a
  /// caller bypassed the packing — fail the publish instead of shipping a
  /// tree the runtime L1 validator would reject when the section opens.
  void _assertPlanWithinLimits(List<OfficialAnkiProjectedItem> items) {
    final unitsPerSection = <String, Set<String>>{};
    final lessonsPerUnit = <String, Set<String>>{};
    for (final item in items) {
      unitsPerSection
          .putIfAbsent(item.sectionId, () => <String>{})
          .add(item.unitId);
      lessonsPerUnit
          .putIfAbsent(item.unitId, () => <String>{})
          .add(item.lessonId);
    }
    for (final entry in unitsPerSection.entries) {
      if (entry.value.length > kMaxUnitsPerSection) {
        throw StateError(
          'section ${entry.key} would hold ${entry.value.length} units '
          '(max $kMaxUnitsPerSection)',
        );
      }
    }
    for (final entry in lessonsPerUnit.entries) {
      if (entry.value.length > kMaxLessonsPerUnit) {
        throw StateError(
          'unit ${entry.key} would hold ${entry.value.length} lessons '
          '(max $kMaxLessonsPerUnit)',
        );
      }
    }
  }

  Future<void> deleteOfficialProjection(String sourceId) async {
    await course.transaction(() async {
      await course.customStatement(
        'DELETE FROM vocabulary WHERE id IN '
        '(SELECT word_id FROM official_anki_projection_index '
        ' WHERE source_id = ?)',
        [sourceId],
      );
      await _deleteOwnedTree(sourceId);
      await course.customStatement(
        'DELETE FROM official_anki_projection_index WHERE source_id = ?',
        [sourceId],
      );
      await course.customStatement(
        'DELETE FROM official_anki_projection_manifest WHERE source_id = ?',
        [sourceId],
      );
    });
  }

  /// P5F-22: the projection's own card list with real tree ids and the
  /// projected presentation kind, in stable card-id order.
  Future<List<OfficialAnkiProjectionIndexRow>> listIndexRows(
    String sourceId,
  ) async {
    final rows = await course.customSelect(
      'SELECT card_id, word_id, section_id, unit_id, lesson_id, '
      'projection_kind FROM official_anki_projection_index '
      'WHERE source_id = ? ORDER BY card_id',
      variables: [Variable(sourceId)],
    ).get();
    return [
      for (final row in rows)
        OfficialAnkiProjectionIndexRow(
          cardId: row.read<int>('card_id'),
          wordId: row.read<String>('word_id'),
          sourceId: sourceId,
          sectionId: row.read<String>('section_id'),
          unitId: row.read<String>('unit_id'),
          lessonId: row.read<String>('lesson_id'),
          kind: row.read<String>('projection_kind'),
        ),
    ];
  }

  /// P0 lesson→cards read: the projection index rows of one lesson, in
  /// stable card-id order. Empty for lessons this database never projected
  /// (legacy imports, synthetic lessons) — never a substitute for those.
  Future<List<OfficialAnkiProjectionIndexRow>> indexRowsForLesson(
    String lessonId,
  ) async {
    final rows = await course.customSelect(
      'SELECT source_id, card_id, word_id, section_id, unit_id, lesson_id, '
      'projection_kind FROM official_anki_projection_index '
      'WHERE lesson_id = ? ORDER BY card_id',
      variables: [Variable(lessonId)],
    ).get();
    return [
      for (final row in rows)
        OfficialAnkiProjectionIndexRow(
          cardId: row.read<int>('card_id'),
          wordId: row.read<String>('word_id'),
          sourceId: row.read<String>('source_id'),
          sectionId: row.read<String>('section_id'),
          unitId: row.read<String>('unit_id'),
          lessonId: row.read<String>('lesson_id'),
          kind: row.read<String>('projection_kind'),
        ),
    ];
  }

  Future<void> _deleteOwnedTree(String sourceId) async {
    final old = await course.customSelect(
      'SELECT DISTINCT section_id, unit_id, lesson_id '
      'FROM official_anki_projection_index WHERE source_id = ?',
      variables: [Variable(sourceId)],
    ).get();
    final sectionIds = {
      for (final row in old)
        if (officialAnkiIsOwnedTreeId(
          sourceId: sourceId,
          id: row.read<String>('section_id'),
        ))
          row.read<String>('section_id'),
    };
    final unitIds = {
      for (final row in old)
        if (officialAnkiIsOwnedTreeId(
          sourceId: sourceId,
          id: row.read<String>('unit_id'),
        ))
          row.read<String>('unit_id'),
    };
    final lessonIds = {
      for (final row in old)
        if (officialAnkiIsOwnedTreeId(
          sourceId: sourceId,
          id: row.read<String>('lesson_id'),
        ))
          row.read<String>('lesson_id'),
    };
    // Doc 38 P5: one chunked DELETE ... IN per table instead of one awaited
    // statement per lesson/unit/section.
    await _deleteIdsChunked('lesson_contents', 'lesson_id', lessonIds);
    await _deleteIdsChunked('lessons', 'id', lessonIds);
    await _deleteIdsChunked('units', 'id', unitIds);
    await _deleteIdsChunked('sections', 'id', sectionIds);
  }

  /// [table]/[column] are hardcoded literals from [_deleteOwnedTree]; ids
  /// are bound parameters in ≤200-element IN lists.
  Future<void> _deleteIdsChunked(
    String table,
    String column,
    Set<String> ids,
  ) async {
    const chunkSize = 200;
    final ordered = ids.toList()..sort();
    for (var start = 0; start < ordered.length; start += chunkSize) {
      final chunk = ordered.skip(start).take(chunkSize).toList();
      final placeholders = List.filled(chunk.length, '?').join(',');
      await course.customStatement(
        'DELETE FROM $table WHERE $column IN ($placeholders)',
        chunk,
      );
    }
  }

  void _assertOwned(String sourceId, String id) {
    if (!officialAnkiIsOwnedTreeId(sourceId: sourceId, id: id)) {
      throw StateError('refusing to write non-official id $id');
    }
  }
}
