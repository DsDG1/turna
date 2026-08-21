import 'package:drift/drift.dart';
import 'package:turna/application/anki/card_introduction_store.dart';
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
  });

  final String sourceId;
  final Set<String> sectionIds;
  final int itemCount;
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
    return OfficialProjectionSummary(
      sourceId: sourceId,
      sectionIds: {
        for (final row in rows) row.read<String>('section_id'),
      },
      itemCount: rows.length,
    );
  }

  Future<void> replaceOfficialProjection({
    required String sourceId,
    required OfficialAnkiProjectionPlan plan,
    String sourceFingerprint = '',
    int projectionVersion = 1,
    int publishedAtMillis = 0,
  }) async {
    await course.transaction(() async {
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
    );
  }

  Future<void> deleteOfficialProjection(String sourceId) async {
    await course.transaction(() async {
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
