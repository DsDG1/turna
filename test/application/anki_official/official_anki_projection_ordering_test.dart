// P0/P1 course-tree write fixes: semantic (natural-name) tree ordering,
// 60/40 packing before publish, section sort-order baseline + compaction,
// and the manifest-ghost rebuild (catalog fingerprint no-op guard).

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_import/recognition/recognize/recognizer.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_repository.dart';

import '../../helpers/in_memory_course_db.dart';

OfficialAnkiProjectionRow _row(
  int cardId,
  List<String> deckPath, {
  List<String> tags = const [],
}) {
  return OfficialAnkiProjectionRow(
    cardId: cardId,
    noteId: cardId,
    noteGuid: 'g$cardId',
    notetypeId: 1,
    deckId: 1,
    deckPath: deckPath,
    templateOrdinal: 0,
    tags: tags,
    fields: ['t$cardId', 'n'],
    sourceFingerprint: 'f$cardId',
  );
}

OfficialAnkiProjectionPlan _project(
  List<OfficialAnkiProjectionRow> rows, {
  OfficialAnkiProjectionProjector? projector,
}) {
  const schema = OfficialAnkiProjectionSchema(
    notetypeId: 1,
    name: 'Basic',
    kind: 'normal',
    fieldNames: ['Front', 'Back'],
    templateNames: ['Card 1'],
    schemaFingerprint: 'fp',
  );
  return (projector ?? OfficialAnkiProjectionProjector()).project(
    sourceId: 'src1',
    profileId: 'profile-a',
    rows: rows,
    mappings: {1: officialAnkiSuggestMapping(schema, const CardRecognizer())},
  );
}

OfficialAnkiProjectedItem _treeItem(
  int cardId, {
  required String sectionId,
  required String unitId,
  required String lessonId,
  required String sectionName,
  required String unitName,
}) {
  return OfficialAnkiProjectedItem(
    kind: OfficialAnkiProjectionKind.showWord,
    cardId: cardId,
    wordId: 'official-anki-profile-a-c$cardId',
    sectionId: sectionId,
    unitId: unitId,
    lessonId: lessonId,
    sectionName: sectionName,
    unitName: unitName,
    lessonName: 'Lesson',
    payload: <String, Object?>{'runtimeType': 'ShowWord', 'id': 'i$cardId'},
    sourceFingerprint: 'fp',
  );
}

Future<List<(String, int)>> _sectionOrders(CourseDatabase db) async {
  final rows = await db.customSelect(
    'SELECT id, sort_order FROM sections ORDER BY sort_order, id',
  ).get();
  return [
    for (final row in rows) (row.read<String>('id'), row.read<int>('sort_order')),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  group('projector semantic ordering', () {
    test('sections and units sort by natural name, not id hash', () {
      final plan = _project([
        _row(1, const ['Course', 'Unit 10']),
        _row(2, const ['Course', 'Unit 2']),
        _row(3, const ['Another', 'Alpha']),
        _row(4, const ['Course', 'unit 1']),
      ]);
      final seen = [
        for (final item in plan.items) '${item.sectionName}›${item.unitName}',
      ];
      expect(seen, [
        'Another›Alpha',
        'Course›unit 1',
        'Course›Unit 2',
        'Course›Unit 10',
      ]);
    });
  });

  group('projector limit packing', () {
    test('sections beyond the unit ceiling split into Part sections', () {
      final rows = [
        for (var i = 1; i <= 8; i++) _row(i, ['Big', 'Sub $i']),
      ];
      final plan = _project(
        rows,
        projector: OfficialAnkiProjectionProjector(maxUnitsPerSection: 3),
      );
      final unitsPerSection = <String, Set<String>>{};
      final sectionOrder = <String>[];
      final names = <String, String>{};
      for (final item in plan.items) {
        if (!unitsPerSection.containsKey(item.sectionId)) {
          sectionOrder.add(item.sectionId);
          names[item.sectionId] = item.sectionName;
        }
        unitsPerSection
            .putIfAbsent(item.sectionId, () => <String>{})
            .add(item.unitId);
      }
      expect(sectionOrder, hasLength(3));
      expect(sectionOrder[1], '${sectionOrder[0]}-x2');
      expect(sectionOrder[2], '${sectionOrder[0]}-x3');
      expect(names[sectionOrder[0]], 'Big');
      expect(names[sectionOrder[1]], 'Big (Part 2)');
      expect(names[sectionOrder[2]], 'Big (Part 3)');
      expect(unitsPerSection[sectionOrder[0]], hasLength(3));
      expect(unitsPerSection[sectionOrder[1]], hasLength(3));
      expect(unitsPerSection[sectionOrder[2]], hasLength(2));
    });

    test('units beyond the lesson ceiling split into Part units', () {
      // 45 cards / lessonSize 20 → 3 lessons in one unit.
      final rows = [
        for (var i = 1; i <= 45; i++) _row(i, const ['Solo', 'Only']),
      ];
      final plan = _project(
        rows,
        projector: OfficialAnkiProjectionProjector(maxLessonsPerUnit: 2),
      );
      final lessonsPerUnit = <String, Set<String>>{};
      final unitOrder = <String>[];
      final names = <String, String>{};
      for (final item in plan.items) {
        if (!lessonsPerUnit.containsKey(item.unitId)) {
          unitOrder.add(item.unitId);
          names[item.unitId] = item.unitName;
        }
        lessonsPerUnit
            .putIfAbsent(item.unitId, () => <String>{})
            .add(item.lessonId);
      }
      expect(unitOrder, hasLength(2));
      expect(unitOrder[1], '${unitOrder[0]}-x2');
      expect(names[unitOrder[0]], 'Only');
      expect(names[unitOrder[1]], 'Only (Part 2)');
      for (final lessons in lessonsPerUnit.values) {
        expect(lessons.length, lessThanOrEqualTo(2));
      }
      // Section membership is untouched by unit splitting.
      expect(
        plan.items.map((i) => i.sectionId).toSet(),
        hasLength(1),
      );
    });

    test('groups within the limits keep byte-identical ids', () {
      final rows = [
        for (var i = 1; i <= 5; i++) _row(i, const ['Course', 'Unit 1']),
      ];
      final plan = _project(
        rows,
        projector: OfficialAnkiProjectionProjector(
          maxUnitsPerSection: 3,
          maxLessonsPerUnit: 3,
        ),
      );
      expect(
        plan.items.map((i) => i.sectionId).toSet(),
        {
          officialAnkiSectionIdForTopDeck(
            sourceId: 'src1',
            topDeckName: 'Course',
          ),
        },
      );
      expect(
        plan.items.map((i) => i.unitId).toSet(),
        hasLength(1),
      );
      expect(
        plan.items.every((i) => !i.sectionId.contains('-x')),
        isTrue,
      );
    });
  });

  group('store sort-order baseline and compaction', () {
    test('first publish appends after existing sections and compacts', () async {
      final db = CourseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      for (var i = 0; i < 3; i++) {
        await db.customStatement(
          "INSERT INTO sections (id, name, level, sort_order) "
          "VALUES ('builtin-$i', 'B$i', '', ?)",
          [i],
        );
      }
      final store = OfficialAnkiCourseProjectionStore(db);
      await store.replaceOfficialProjection(
        sourceId: 's1',
        plan: OfficialAnkiProjectionPlan(
          items: [
            _treeItem(
              1,
              sectionId: 'official-anki-s1-s1',
              unitId: 'official-anki-s1-u1',
              lessonId: 'official-anki-s1-l1-p1',
              sectionName: 'Official A',
              unitName: 'U1',
            ),
            _treeItem(
              2,
              sectionId: 'official-anki-s1-s2',
              unitId: 'official-anki-s1-u2',
              lessonId: 'official-anki-s1-l2-p1',
              sectionName: 'Official B',
              unitName: 'U1',
            ),
          ],
          issues: const [],
        ),
        sourceFingerprint: 'fp',
      );
      final orders = await _sectionOrders(db);
      expect(orders.map((o) => o.$1).toList(), [
        'builtin-0',
        'builtin-1',
        'builtin-2',
        'official-anki-s1-s1',
        'official-anki-s1-s2',
      ]);
      expect(
        orders.map((o) => o.$2).toSet(),
        {for (var i = 0; i < orders.length; i++) i},
        reason: 'compaction must produce a dense 0..n-1 order',
      );
    });

    test('republish keeps the source position and absorbs growth', () async {
      final db = CourseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      for (var i = 0; i < 3; i++) {
        await db.customStatement(
          "INSERT INTO sections (id, name, level, sort_order) "
          "VALUES ('builtin-$i', 'B$i', '', ?)",
          [i],
        );
      }
      final store = OfficialAnkiCourseProjectionStore(db);
      Future<void> publish(List<String> sectionIds) async {
        await store.replaceOfficialProjection(
          sourceId: 's1',
          plan: OfficialAnkiProjectionPlan(
            items: [
              for (var i = 0; i < sectionIds.length; i++)
                _treeItem(
                  i + 1,
                  sectionId: sectionIds[i],
                  unitId: 'official-anki-s1-u$i',
                  lessonId: 'official-anki-s1-l$i-p1',
                  sectionName: 'Official $i',
                  unitName: 'U1',
                ),
            ],
            issues: const [],
          ),
          sourceFingerprint: 'fp-${sectionIds.length}',
        );
      }

      await publish(['official-anki-s1-sA', 'official-anki-s1-sB']);
      // Same source republishes with one more section than before.
      await publish([
        'official-anki-s1-sA',
        'official-anki-s1-sB',
        'official-anki-s1-sC',
      ]);
      final orders = await _sectionOrders(db);
      expect(orders, hasLength(6));
      expect(orders.first.$1, 'builtin-0');
      expect(orders[3].$1, 'official-anki-s1-sA');
      expect(orders[5].$1, 'official-anki-s1-sC');
      expect(orders.map((o) => o.$2).toSet(), {
        for (var i = 0; i < 6; i++) i,
      });
    });

    test('colliding sort orders from older publishes are healed', () async {
      final db = CourseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      // Pre-v3 publishes started every source at 0: duplicate orders.
      await db.customStatement(
        "INSERT INTO sections (id, name, level, sort_order) "
        "VALUES ('old-a', 'A', '', 0), ('old-b', 'B', '', 0), "
        "('old-c', 'C', '', 1)",
      );
      final store = OfficialAnkiCourseProjectionStore(db);
      await store.replaceOfficialProjection(
        sourceId: 's1',
        plan: OfficialAnkiProjectionPlan(
          items: [
            _treeItem(
              1,
              sectionId: 'official-anki-s1-s1',
              unitId: 'official-anki-s1-u1',
              lessonId: 'official-anki-s1-l1-p1',
              sectionName: 'Official',
              unitName: 'U1',
            ),
          ],
          issues: const [],
        ),
        sourceFingerprint: 'fp',
      );
      final orders = await _sectionOrders(db);
      expect(orders, hasLength(4));
      expect(orders.map((o) => o.$2).toSet(), {
        for (var i = 0; i < 4; i++) i,
      });
    });

    test('a plan violating the ceilings fails the publish', () async {
      final db = CourseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = OfficialAnkiCourseProjectionStore(db);
      // 61 units in one section: one past kMaxUnitsPerSection.
      final items = [
        for (var i = 0; i < 61; i++)
          _treeItem(
            i + 1,
            sectionId: 'official-anki-s1-s1',
            unitId: 'official-anki-s1-u$i',
            lessonId: 'official-anki-s1-l$i-p1',
            sectionName: 'Too Big',
            unitName: 'U$i',
          ),
      ];
      await expectLater(
        store.replaceOfficialProjection(
          sourceId: 's1',
          plan: OfficialAnkiProjectionPlan(items: items, issues: const []),
          sourceFingerprint: 'fp',
        ),
        throwsA(isA<StateError>()),
      );
      final sections = await db
          .customSelect('SELECT COUNT(*) AS n FROM sections')
          .getSingle();
      expect(sections.read<int>('n'), 0, reason: 'transaction must roll back');
    });
  });

  group('repository deterministic ordering', () {
    test('sectionShells breaks sort-order ties by id', () async {
      final db = CourseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customStatement(
        "INSERT INTO sections (id, name, level, sort_order) "
        "VALUES ('zz', 'Z', '', 0), ('aa', 'A', '', 0), ('mm', 'M', '', 1)",
      );
      final shells = await CourseRepository(db).sectionShells();
      expect(shells.map((s) => s.id).toList(), ['aa', 'zz', 'mm']);
    });
  });

  group('service manifest ghost rebuild', () {
    test('missing manifest makes the fingerprint no-op republish', () async {
      final catalog = OfficialAnkiDatabase.memory();
      addTearDown(catalog.close);
      OfficialAnkiSourceDao(catalog).upsertSource(
        sourceId: 'src1',
        profileId: 'profile-a',
        sourceHash: 'h',
        sourceSize: 1,
        displayName: 'src',
        state: 'active',
        backendCommit: '967aa0d578fc75181e292e95326f9b58698da25c',
        nowMillis: 1,
      );
      OfficialAnkiSourceDao(catalog).replaceCards(
        sourceId: 'src1',
        cards: [
          OfficialAnkiCardDescriptor(
            cardId: 1,
            noteId: 1,
            deckId: 1,
            templateOrd: 0,
            noteGuid: 'guid-1',
          ),
        ],
      );
      final course = CourseDatabase(NativeDatabase.memory());
      addTearDown(course.close);
      final fake = FakeOfficialAnkiEngine();
      fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
      final service = OfficialAnkiCourseProjectionService(
        engine: fake,
        catalog: catalog,
        course: course,
        sourceId: 'src1',
        profileId: 'profile-a',
        flags: const OfficialAnkiFeatureFlags(
          engine: true,
          import: true,
          catalogReady: true,
          runtimeCapable: true,
          projection: true,
        ),
      );
      const schema = OfficialAnkiProjectionSchema(
        notetypeId: 1,
        name: 'Basic',
        kind: 'normal',
        fieldNames: ['Front', 'Back'],
        templateNames: ['Card 1'],
        schemaFingerprint: 'fake-basic',
      );
      service.confirmMapping(
        schema: schema,
        suggestion: officialAnkiSuggestMapping(schema, const CardRecognizer()),
      );

      final first = await service.projectSource();
      expect(first.noop, isFalse);
      expect(first.itemCount, greaterThan(0));
      // The section id uses the deck-tree deckId, not the hash fallback.
      final sectionIds = await course.customSelect(
        'SELECT DISTINCT section_id FROM official_anki_projection_index',
      ).get();
      expect(sectionIds.single.read<String>('section_id'), 'official-anki-src1-s1');

      final second = await service.projectSource();
      expect(second.noop, isTrue, reason: 'unchanged source stays a no-op');

      // Simulate the seeder wipe: course tables die, catalog state survives.
      await course.customStatement('DELETE FROM lesson_contents');
      await course.customStatement('DELETE FROM lessons');
      await course.customStatement('DELETE FROM units');
      await course.customStatement('DELETE FROM sections');
      await course.customStatement(
        'DELETE FROM official_anki_projection_manifest',
      );
      await course.customStatement(
        'DELETE FROM official_anki_projection_index',
      );
      final ghost = await service.projectSource();
      expect(ghost.noop, isFalse, reason: 'missing manifest must rebuild');
      expect(ghost.itemCount, first.itemCount);
      final rebuilt = await course.customSelect(
        'SELECT COUNT(*) AS n FROM official_anki_projection_index',
      ).getSingle();
      expect(rebuilt.read<int>('n'), greaterThan(0));
    });
  });
}
