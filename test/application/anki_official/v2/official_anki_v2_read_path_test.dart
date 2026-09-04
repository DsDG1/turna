import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/projection/official_anki_lesson_card_index.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_course_read.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_store.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';

import '../../../helpers/in_memory_course_db.dart';

/// step4.md B6：读面分叉——flag 关 = v1 原样（零回归），flag 开 = 视图供
/// 课程树 / 复习链课时→卡映射。挂载点 = `OfficialAnkiLessonCardIndex`
/// （复习链 P0 单源，复习页/练习中心真实消费的解析面）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late OfficialAnkiDatabase catalog;
  late CourseDatabase course;

  const sourceId = 'src-v2-read';
  const lessonId = 'official-anki-src-v2-read-l-abc-p1';
  const part2Id = 'official-anki-src-v2-read-l-abc-p2';
  const part3Id = 'official-anki-src-v2-read-l-abc-p3';
  const otherLessonId = 'official-anki-legacy-l-xyz-p1';


  setUp(() async {
    catalog = OfficialAnkiDatabase.memory();
    course = CourseDatabase(NativeDatabase.memory());
    if (!getIt.isRegistered<CourseDatabase>()) {
      getIt.registerSingleton<CourseDatabase>(course);
    }
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    OfficialAnkiCompositionRoot.locatorPaths = OfficialAnkiPaths(
      profileId: 'profile-v2-read',
      profileRoot: Directory.systemTemp.createTempSync('turna-v2-read-'),
    );

    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: sourceId,
      profileId: 'profile-v2-read',
      sourceHash: 'hash-read',
      sourceSize: 10,
      displayName: 'Read',
      state: 'active',
      backendCommit: 'pending',
      nowMillis: 1,
    );
    sources.markChainV2(sourceId: sourceId, nowMillis: 1);

    await OfficialAnkiV2ViewStore(course).replaceAll(
      rows: [
        const OfficialAnkiV2ViewRow(
          sourceId: sourceId,
          cardId: 7,
          noteId: 70,
          deckId: 10,
          wordId: 'w-7',
          sectionKey: 'Deck A',
          sectionId: 'official-anki-src-v2-read-s-111',
          unitId: 'official-anki-src-v2-read-u-222',
          lessonId: lessonId,
          lessonKey: 'Deck A',
          presentationKind: 'showWord',
          sourceHash: 'hash-read',
        ),
        const OfficialAnkiV2ViewRow(
          sourceId: sourceId,
          cardId: 9,
          noteId: 90,
          deckId: 10,
          wordId: 'w-9',
          sectionKey: 'Deck A',
          sectionId: 'official-anki-src-v2-read-s-111',
          unitId: 'official-anki-src-v2-read-u-222',
          lessonId: lessonId,
          lessonKey: 'Deck A',
          presentationKind: 'showWord',
          sourceHash: 'hash-read',
        ),
      ],
      rebuiltAtMillis: 1,
    );
  });

  tearDown(() async {
    OfficialAnkiCompositionRoot.readOnlyCatalog = null;
    OfficialAnkiCompositionRoot.locatorPaths = null;
    OfficialAnkiLessonCardIndex.debugResolver = null;
    await getIt.reset();
  });

  test('flag on: lesson card index resolves from the view (stable order)',
      () async {
    final index = await OfficialAnkiLessonCardIndex.resolveForLesson(lessonId);
    expect(index, isNotNull);
    expect(index!.cardIds, [7, 9], reason: '稳定 card-id 序');
    expect(index.sourceId, sourceId);
    expect(index.cardIdForInteractionId('w-7'), 7);
  });

  test('flag on: non-v2 lesson falls through to the v1 projection index',
      () async {
    // 视图里没有 otherLessonId → 返回 null（该库从未投影过它），
    // 证明 v1 读面未被劫持。
    final index =
        await OfficialAnkiLessonCardIndex.resolveForLesson(otherLessonId);
    expect(index, isNull);
  });

  test('flag on: section shells synthesize from the view', () async {
    final read = OfficialAnkiV2CourseRead(catalog: catalog, course: course);
    final shells = await read.sectionShells();
    expect(shells, hasLength(1));
    expect(shells.single.name, 'Deck A');
    expect(shells.single.level, 'OfficialAnki');
    expect(shells.single.units, hasLength(1));
    expect(shells.single.units.single.lessons, hasLength(1));
    expect(shells.single.units.single.lessons.single.id, lessonId);

    final activeIds = await read.activeSectionIds();
    expect(activeIds, contains('official-anki-src-v2-read-s-111'));
  });

  test('flag on: retiring source disappears from shells and mapping',
      () async {
    OfficialAnkiSourceDao(catalog)
        .markRetiring(sourceId: sourceId, nowMillis: 2);
    final read = OfficialAnkiV2CourseRead(catalog: catalog, course: course);
    expect(await read.sectionShells(), isEmpty,
        reason: 'K6：retiring 即刻从课程树消失（账本 state 过滤兜底）');
    final index = await OfficialAnkiLessonCardIndex.resolveForLesson(lessonId);
    // 视图行还在（等 job 重建清理），但卡映射读面按账本过滤。
    // lessonCardEntriesForLesson 过滤后为空 → index 为 null。
    expect(index, isNull);
  });

  test('flag on: same-key lesson parts list in card order with (n) suffix',
      () async {
    // 同一 unit、同一 lessonKey 的三个 part 片；cardId 序 ≠ lesson_id
    // hash 序（p1 < p3 < p2 按首卡），树壳必须按首卡排序并加 (n) 后缀。
    OfficialAnkiV2ViewRow partRow(String id, int cardId, int noteId) =>
        OfficialAnkiV2ViewRow(
          sourceId: sourceId,
          cardId: cardId,
          noteId: noteId,
          deckId: 10,
          wordId: 'w-$cardId',
          sectionKey: 'Deck A',
          sectionId: 'official-anki-src-v2-read-s-111',
          unitId: 'official-anki-src-v2-read-u-222',
          lessonId: id,
          lessonKey: 'Deck A',
          presentationKind: 'showWord',
          sourceHash: 'hash-read',
        );

    await OfficialAnkiV2ViewStore(course).replaceAll(
      rows: [
        const OfficialAnkiV2ViewRow(
          sourceId: sourceId,
          cardId: 7,
          noteId: 70,
          deckId: 10,
          wordId: 'w-7',
          sectionKey: 'Deck A',
          sectionId: 'official-anki-src-v2-read-s-111',
          unitId: 'official-anki-src-v2-read-u-222',
          lessonId: lessonId,
          lessonKey: 'Deck A',
          presentationKind: 'showWord',
          sourceHash: 'hash-read',
        ),
        partRow(part3Id, 11, 110),
        partRow(part2Id, 12, 120),
      ],
      rebuiltAtMillis: 2,
    );

    final shells = await OfficialAnkiV2CourseRead(
      catalog: catalog,
      course: course,
    ).sectionShells();
    final lessons = shells.single.units.single.lessons;
    expect(lessons.map((l) => l.id).toList(), [
      lessonId, // 首卡 7
      part3Id, // 首卡 11
      part2Id, // 首卡 12
    ], reason: 'hash lesson_id 序 ≠ 卡序，按组内首卡排序');
    expect(lessons.map((l) => l.name).toList(), [
      'Deck A (1)',
      'Deck A (2)',
      'Deck A (3)',
    ]);
  });

  test('flag on: units list in first-card order within a section', () async {
    const unitLate = 'official-anki-src-v2-read-u-late';
    await OfficialAnkiV2ViewStore(course).replaceAll(
      rows: [
        ...await OfficialAnkiV2ViewStore(course).rowsForLesson(lessonId),
        const OfficialAnkiV2ViewRow(
          sourceId: sourceId,
          cardId: 30,
          noteId: 300,
          deckId: 12,
          wordId: 'w-30',
          sectionKey: 'Deck A',
          sectionId: 'official-anki-src-v2-read-s-111',
          unitId: unitLate,
          lessonId: 'official-anki-src-v2-read-l-late-p1',
          lessonKey: 'Deck A::Sub',
          presentationKind: 'showWord',
          sourceHash: 'hash-read',
        ),
      ],
      rebuiltAtMillis: 2,
    );

    final shells = await OfficialAnkiV2CourseRead(
      catalog: catalog,
      course: course,
    ).sectionShells();
    expect(shells.single.units.map((u) => u.id).toList(), [
      'official-anki-src-v2-read-u-222', // 首卡 7
      unitLate, // 首卡 30
    ]);
  });
}
