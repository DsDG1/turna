import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_config_keys.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_rebuilder.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_store.dart';
import 'package:turna/data/course_database.dart';

import '../../../helpers/in_memory_course_db.dart';

/// step4.md B3：视图 DROP+REBUILD 的幂等 / 取消 / 占位 / retiring 排除。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late OfficialAnkiDatabase catalog;
  late CourseDatabase course;
  late FakeOfficialAnkiEngine engine;
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('turna-v2-view-');
    catalog = OfficialAnkiDatabase.memory();
    course = CourseDatabase(NativeDatabase.memory());
    engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: 'pkg.apkg', notes: 2, cards: 2);
    engine.deckTree = const [
      OfficialAnkiDeckNode(deckId: 10, name: 'Deck A', level: 0),
    ];
  });

  tearDown(() {
    catalog.close();
    course.close();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  String seedActiveV2Source({
    String sourceId = 'src-v2-a',
    String state = 'active',
  }) {
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: sourceId,
      profileId: 'profile-v2-view',
      sourceHash: 'hash-$sourceId',
      sourceSize: 10,
      displayName: 'A',
      state: state,
      backendCommit: 'pending',
      nowMillis: 1,
    );
    OfficialAnkiSourceDao(catalog)
        .markChainV2(sourceId: sourceId, nowMillis: 1);
    OfficialAnkiSourceDao(catalog).upsertCardBatch(
      sourceId: sourceId,
      cards: [
        const OfficialAnkiCardDescriptor(
          cardId: 101,
          noteId: 11,
          deckId: 10,
          templateOrd: 0,
          notetypeId: 1,
        ),
        const OfficialAnkiCardDescriptor(
          cardId: 102,
          noteId: 12,
          deckId: 10,
          templateOrd: 0,
          notetypeId: 1,
        ),
      ],
    );
    return sourceId;
  }

  OfficialAnkiV2ViewRebuilder rebuilder({int? lessonSize}) =>
      OfficialAnkiV2ViewRebuilder(
        engine: engine,
        catalog: catalog,
        course: course,
        profileId: 'profile-v2-view',
        lessonSize: lessonSize ?? OfficialAnkiV2ViewRebuilder.defaultLessonSize,
      );

  /// 独立 source：一个牌组里 seed 指定 cardId 的卡（notetype 1）。
  void seedSourceWithCards(
    String sourceId, {
    int deckId = 10,
    required List<int> cardIds,
  }) {
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: sourceId,
      profileId: 'profile-v2-view',
      sourceHash: 'hash-$sourceId',
      sourceSize: 10,
      displayName: sourceId,
      state: 'active',
      backendCommit: 'pending',
      nowMillis: 1,
    );
    OfficialAnkiSourceDao(catalog).markChainV2(
      sourceId: sourceId,
      nowMillis: 1,
    );
    OfficialAnkiSourceDao(catalog).upsertCardBatch(
      sourceId: sourceId,
      cards: [
        for (var i = 0; i < cardIds.length; i++)
          OfficialAnkiCardDescriptor(
            cardId: cardIds[i],
            noteId: 1000 + i,
            deckId: deckId,
            templateOrd: 0,
            notetypeId: 1,
          ),
      ],
    );
  }

  test('rebuild is idempotent: same input, same rows, twice', () async {
    seedActiveV2Source();
    final first = await rebuilder().rebuild();
    final second = await rebuilder().rebuild();
    expect(first.rowCount, 2);
    expect(second.rowCount, 2, reason: 'K3：重跑即收敛');
    expect(first.cancelled, isFalse);
    final store = OfficialAnkiV2ViewStore(course);
    expect(await store.cardCountForSource('src-v2-a'), 2);
    // owned-tree id 规则：section id 能被 v1 过滤器识别。
    final ids = await store.sectionSummaries();
    expect(ids.single.sectionId, startsWith('official-anki-src-v2-a-'));
  });

  test('rebuild drops rows of removed sources (atomic swap)', () async {
    final a = seedActiveV2Source(sourceId: 'src-v2-a');
    await rebuilder().rebuild();
    final store = OfficialAnkiV2ViewStore(course);
    expect(await store.cardCountForSource(a), 2);

    // 终删 a 的账本行 → 重建后视图不再有它。
    OfficialAnkiSourceDao(catalog).deleteSourceV2(sourceId: a);
    final result = await rebuilder().rebuild();
    expect(result.sourceCount, 0);
    expect(result.rowCount, 0);
    expect(await store.isAvailable, isFalse);
  });

  test('retiring sources are excluded immediately (K6)', () async {
    final a = seedActiveV2Source();
    seedActiveV2Source(sourceId: 'src-v2-b');
    await rebuilder().rebuild();
    // a 进入 retiring（B5 ①的 CAS）。
    OfficialAnkiSourceDao(catalog)
        .markRetiring(sourceId: a, nowMillis: 2);
    final result = await rebuilder().rebuild();
    expect(result.sourceCount, 1, reason: 'retiring 的 source 即刻不可见');
    expect(
      await OfficialAnkiV2ViewStore(course).cardCountForSource(a),
      0,
    );
  });

  test('cancel token aborts before any write (K13 cancel channel)', () async {
    seedActiveV2Source();
    final token = OfficialAnkiV2ViewRebuildCancelToken()..cancel();
    final result = await rebuilder().rebuild(cancelToken: token);
    expect(result.cancelled, isTrue);
    expect(result.rowCount, 0);
    expect(await OfficialAnkiV2ViewStore(course).isAvailable, isFalse,
        reason: '取消不得留下半建视图');
  });

  test('rebuilding placeholder toggles around the run (K11)', () async {
    seedActiveV2Source();
    final observed = <bool>[];
    OfficialAnkiV2ViewRebuilder.rebuilding.addListener(() {
      observed.add(OfficialAnkiV2ViewRebuilder.rebuilding.value);
    });
    await rebuilder().rebuild();
    expect(observed.first, isTrue, reason: '重建开始 → 占位信号');
    expect(observed.last, isFalse, reason: '重建结束 → 信号回落');
    expect(OfficialAnkiV2ViewRebuilder.rebuilding.value, isFalse);
  });

  test('v1-only catalog yields an empty view and flag-off readers stay v1',
      () async {
    // 只有 v1 source（chain 默认 v1）：视图重建结果为空——v1 读面不受影响。
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src-v1-x',
      profileId: 'profile-v2-view',
      sourceHash: 'hash-x',
      sourceSize: 10,
      displayName: 'X',
      state: 'active',
      backendCommit: 'pending',
      nowMillis: 1,
    );
    catalog.handle.execute("UPDATE anki_sources SET chain = 'v1' WHERE source_id = 'src-v1-x'");
    final result = await rebuilder().rebuild();
    expect(result.sourceCount, 0);
    expect(result.rowCount, 0);
  });

  test('flat deck splits into lessonSize chunks in stable cardId order',
      () async {
    seedSourceWithCards('src-split', cardIds: [105, 101, 104, 102, 103]);
    final store = OfficialAnkiV2ViewStore(course);
    await rebuilder(lessonSize: 2).rebuild();

    final lessonIds = (await store.lessonIds()).toList();
    expect(lessonIds, hasLength(3), reason: '5 张卡、每课时 2 张 → 3 课时');

    // 组内按 cardId 稳定序切片（seed 顺序打乱也不影响分组）。
    final members = {
      for (final id in lessonIds)
        id: [for (final row in await store.rowsForLesson(id)) row.cardId],
    };
    final grouped = members.values.map((e) => (e.join(','))).toSet();
    expect(grouped, {'101,102', '103,104', '105'});

    // 首片 part=1，lessonId 与旧「一路径 = 一课时」派生完全一致。
    final flatGroupKey = ['Deck A', 'Deck A', 'Deck A'].join('\u001f');
    final firstPartId = officialAnkiLessonId(
      sourceId: 'src-split',
      groupKey: flatGroupKey,
      part: 1,
    );
    expect(members, containsPair(firstPartId, [101, 102]));

    // 幂等：重跑同输入，3 个课时 id 与成员不变。
    await rebuilder(lessonSize: 2).rebuild();
    final rerun = {
      for (final id in await store.lessonIds())
        id: [for (final row in await store.rowsForLesson(id)) row.cardId],
    };
    expect(rerun, members);
  });

  test('multi-level decks group by last path segment and chunk within',
      () async {
    engine.deckTree = const [
      OfficialAnkiDeckNode(deckId: 10, name: 'Deck A', level: 0),
      OfficialAnkiDeckNode(deckId: 11, name: 'Deck A::B', level: 1),
      OfficialAnkiDeckNode(deckId: 12, name: 'Deck A::B::C', level: 2),
      OfficialAnkiDeckNode(deckId: 13, name: 'Deck A::B::D', level: 2),
    ];
    seedSourceWithCards('src-tree', deckId: 12, cardIds: [201, 202, 203]);
    seedSourceWithCards('src-tree2', deckId: 13, cardIds: [301, 302]);

    final store = OfficialAnkiV2ViewStore(course);
    await rebuilder(lessonSize: 2).rebuild();

    final lessons = <String, List<int>>{
      for (final id in await store.lessonIds())
        id: [for (final row in await store.rowsForLesson(id)) row.cardId],
    };
    expect(lessons, hasLength(3), reason: 'C 切 2 片 + D 1 片');
    expect(lessons.values.map((e) => e.join(',')), {
      '201,202', '203', // C：同末段组内切片
      '301,302', // D：独立末段组
    });
  });

  test('default fallback presentationKind is flip (not showWord)', () async {
    seedActiveV2Source(sourceId: 'src-kind-fallback');
    await rebuilder().rebuild();
    final store = OfficialAnkiV2ViewStore(course);
    final lessonIds = await store.lessonIds();
    final rows = await store.rowsForLesson(lessonIds.first);
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(row.presentationKind, 'flip', reason: '无 mapping 决策时兜底为 flip，非 showWord');
    }
  });

  test('archetype basicPair resolves to flip regardless of enabledKinds order', () async {
    final a = seedActiveV2Source(sourceId: 'src-kind-basic');
    engine.configStore[OfficialAnkiV2ConfigKeys.importMapping(a)] = {
      'schema': 1,
      'confirmed': [1],
      'skipped': [],
      'suggestions': jsonEncode({
        '1': {
          'archetype': 'basicPair',
          'enabledKinds': ['showWord', 'flip', 'multipleChoice'],
        },
      }),
    };
    await rebuilder().rebuild();
    final store = OfficialAnkiV2ViewStore(course);
    final lessonIds = await store.lessonIds();
    final rows = await store.rowsForLesson(lessonIds.first);
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(row.presentationKind, 'flip', reason: 'basicPair 必须解析为 flip 翻转卡');
    }
  });

  test('archetype choice resolves to multipleChoice when enabled', () async {
    final a = seedActiveV2Source(sourceId: 'src-kind-choice');
    engine.configStore[OfficialAnkiV2ConfigKeys.importMapping(a)] = {
      'schema': 1,
      'confirmed': [1],
      'skipped': [],
      'suggestions': jsonEncode({
        '1': {
          'archetype': 'choice',
          'enabledKinds': ['flip', 'multipleChoice'],
        },
      }),
    };
    await rebuilder().rebuild();
    final store = OfficialAnkiV2ViewStore(course);
    final lessonIds = await store.lessonIds();
    final rows = await store.rowsForLesson(lessonIds.first);
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(row.presentationKind, 'multipleChoice', reason: 'choice 且启用选择题必须解析为 multipleChoice');
    }
  });
}
