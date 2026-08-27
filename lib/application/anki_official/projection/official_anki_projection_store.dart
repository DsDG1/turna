import 'package:drift/drift.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_canonical.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
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
    required this.sectionId,
    required this.unitId,
    required this.lessonId,
    required this.kind,
  });

  final int cardId;
  final String wordId;
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
      var sectionOrder = 0;
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
      var unitOrder = 0;
      for (final unit in units.values) {
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
      var lessonOrder = 0;
      for (final entry in lessons.entries) {
        final first = entry.value.first;
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
      for (final item in plan.items) {
        await course.customStatement(
          'INSERT INTO official_anki_projection_index '
          '(source_id, card_id, word_id, section_id, unit_id, lesson_id, '
          'projection_kind, source_fingerprint, projection_version) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)',
          [
            sourceId,
            item.cardId,
            item.wordId,
            item.sectionId,
            item.unitId,
            item.lessonId,
            item.kind.name,
            sourceFingerprint.isEmpty
                ? item.sourceFingerprint
                : sourceFingerprint,
          ],
        );
        statements++;
        tick();
        final vocab = item.vocabulary;
        if (vocab != null) {
          // P5F-33 controlled vocabulary channel: one row per card, tagged
          // `official:<sourceId>`; built-in and legacy rows are never touched
          // because ids are the official word ids and deletes are index-driven.
          await course.customStatement(
            'INSERT OR REPLACE INTO vocabulary '
            '(id, term, translation, pronunciation, audio_asset, tags) '
            "VALUES (?, ?, ?, ?, ?, '[\"official:$sourceId\"]')",
            [
              item.wordId,
              vocab.term,
              vocab.translation,
              vocab.pronunciation,
              vocab.audioAsset,
            ],
          );
          statements++;
          tick();
        }
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
    });
    await CardIntroductionStore.resolve().seedOfficialProjection(
      sourceId: sourceId,
      cardIds: {for (final item in plan.items) item.cardId},
      studiedCardIds: studiedCardIds,
    );
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

  static String lessonContentJson(List<OfficialAnkiProjectedItem> items) {
    return officialAnkiLessonJson(items);
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
    for (final lessonId in lessonIds) {
      await course.customStatement(
        'DELETE FROM lesson_contents WHERE lesson_id = ?',
        [lessonId],
      );
      await course.customStatement('DELETE FROM lessons WHERE id = ?', [lessonId]);
    }
    for (final unitId in unitIds) {
      await course.customStatement('DELETE FROM units WHERE id = ?', [unitId]);
    }
    for (final sectionId in sectionIds) {
      await course.customStatement(
        'DELETE FROM sections WHERE id = ?',
        [sectionId],
      );
    }
  }

  void _assertOwned(String sourceId, String id) {
    if (!officialAnkiIsOwnedTreeId(sourceId: sourceId, id: id)) {
      throw StateError('refusing to write non-official id $id');
    }
  }
}
