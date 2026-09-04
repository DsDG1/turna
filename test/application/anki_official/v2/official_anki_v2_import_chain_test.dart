import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_card_index.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_decision_store.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_import_service.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_store.dart';
import 'package:turna/data/course_database.dart';

import '../../../helpers/in_memory_course_db.dart';

/// step4.md B1+B2：v2 导入链全流程 + **零写入守卫**。
///
/// 守卫两层：
/// 1. catalog 侧 statement 级——sqlite3 `updates` 钩子记录每一次
///    INSERT/UPDATE/DELETE 的表名，断言只命中五表集合；
/// 2. course.db 侧 statement 级——drift `setup` 钩子同样记录，断言除
///    `anki_course_tree_view` 外的 anki 旧表零写入。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late OfficialAnkiDatabase catalog;
  late CourseDatabase course;
  late FakeOfficialAnkiEngine engine;
  late Directory root;
  late OfficialAnkiPaths paths;
  final catalogWrites = <String>{};
  final courseWrites = <String>{};

  setUp(() {
    root = Directory.systemTemp.createTempSync('turna-v2-chain-');
    catalog = OfficialAnkiDatabase.memory();
    course = CourseDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.updatesSync.listen((update) => courseWrites.add(update.tableName));
        },
      ),
    );
    catalog.handle.updatesSync.listen(
      (update) => catalogWrites.add(update.tableName),
    );
    engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: 'pkg.apkg', notes: 3, cards: 4);
    engine.deckTree = const [
      OfficialAnkiDeckNode(deckId: 10, name: 'Turkish Basics', level: 0),
      OfficialAnkiDeckNode(deckId: 11, name: 'Turkish Basics::Unit 1', level: 1),
      OfficialAnkiDeckNode(deckId: 12, name: 'Turkish Basics::Unit 2', level: 1),
      OfficialAnkiDeckNode(deckId: 20, name: 'Solo Deck', level: 0),
    ];
    // seedPackage 固定 deckId=1；重写到测试牌组（1、2 → Unit 1，3、4 → Unit 2）。
    final rewritten = <int, OfficialAnkiCardDescriptor>{
      for (final entry in engine.cards.entries)
        entry.key: OfficialAnkiCardDescriptor(
          cardId: entry.value.cardId,
          noteId: entry.value.noteId,
          deckId: entry.key <= 2 ? 11 : 12,
          templateOrd: entry.value.templateOrd,
          noteGuid: entry.value.noteGuid,
          notetypeId: entry.value.notetypeId,
        ),
    };
    engine.cards
      ..clear()
      ..addAll(rewritten);
    paths = OfficialAnkiPaths(
      profileId: 'profile-v2-01',
      profileRoot: Directory(p.join(root.path, 'live'))..createSync(recursive: true),
    );
  });

  tearDown(() {
    catalog.close();
    course.close();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 模拟 saga.startStaging 已完成的账本状态（staging 段与 v1 共用，
  /// 不在 v2 测试范围）。
  (String, String) seedStagedSource({String sourceId = 'src-v2-1'}) {
    final sources = OfficialAnkiSourceDao(catalog);
    final attempts = OfficialAnkiImportAttemptDao(catalog);
    const attemptId = 'att-v2-1';
    sources.upsertSource(
      sourceId: sourceId,
      profileId: paths.profileId,
      sourceHash: 'hash-1',
      sourceSize: 100,
      displayName: 'Basics',
      state: 'preview_ready',
      backendCommit: 'pending',
      nowMillis: 1,
      activeAttemptId: attemptId,
    );
    attempts.insert(
      attemptId: attemptId,
      sourceId: sourceId,
      requestId: 'req-1',
      state: 'preview_ready',
      nowMillis: 1,
      phase: 'preview_ready',
    );
    return (sourceId, attemptId);
  }

  test('v2 commit: config decisions + ledger 5 tables + view rebuild', () async {
    final (sourceId, attemptId) = seedStagedSource();

    final service = OfficialAnkiV2ImportService(
      catalog: catalog,
      paths: paths,
      course: course,
      engine: engine,
    );
    final result = await service.commit(
      sourceId: sourceId,
      packagePath: 'pkg.apkg',
      displayName: 'Basics',
      confirmedNotetypes: const {1},
    );

    // —— 配置区（B1/D2）——
    expect(
      engine.configStore.containsKey('turna.import.mapping.$sourceId'),
      isTrue,
      reason: '映射晋升必须写进 Collection 配置区',
    );
    // 多级牌组：路径派生已确定，不写决策键（派生键不得压制派生）。
    expect(
      engine.configStore.containsKey('turna.course.placement.10'),
      isFalse,
      reason: '多级树由 deck path 派生，配置区不存冗余决策',
    );
    // 平牌组（无子级）：派生决策落键（可被用户覆盖同键覆写）。
    expect(
      engine.configStore.containsKey('turna.course.placement.20'),
      isTrue,
      reason: '平牌组默认放置决策写进配置区',
    );

    // —— 账本（B2 五表）——
    final sources = OfficialAnkiSourceDao(catalog);
    final source = sources.findById(sourceId);
    expect(source!.chain, 'v2');
    expect(source.state, 'active');
    expect(sources.cardCount(sourceId), 4, reason: '卡索引写 anki_source_cards');
    final attempt = OfficialAnkiImportAttemptDao(catalog).find(attemptId);
    expect(attempt!.state, 'completed');
    expect(
      OfficialAnkiImportAttemptDao(catalog).receiptNoteIds(attemptId),
      isNotEmpty,
      reason: 'K2：receipt note ids 吸收进 attempt 行',
    );

    // —— 视图（B3）——
    final store = OfficialAnkiV2ViewStore(course);
    expect(await store.isAvailable, isTrue);
    expect(await store.cardCountForSource(sourceId), 4);
    final summaries = await store.sectionSummaries();
    expect(summaries, hasLength(1));
    expect(summaries.single.sectionKey, 'Turkish Basics');
    expect(summaries.single.lessonCount, 2,
        reason: '两个子牌组 = 两个课时（deck path 派生）');

    // —— 调度锁：未引入的卡全部挂起（P1 产品语义）——
    expect(engine.suspended, containsAll([1, 2, 3, 4]));

    // —— 结果形状 ——
    expect(result.cardCount, 4);
    expect(result.sectionCount, 1);
  });

  test('zero-write guard: catalog writes touch only the five ledger tables',
      () async {
    final (sourceId, _) = seedStagedSource();
    await OfficialAnkiV2ImportService(
      catalog: catalog,
      paths: paths,
      course: course,
      engine: engine,
    ).commit(
      sourceId: sourceId,
      packagePath: 'pkg.apkg',
      displayName: 'Basics',
    );

    const allowed = <String>{
      'anki_sources',
      'anki_import_attempts',
      'anki_source_cards',
      'anki_maintenance_jobs',
      'anki_maintenance_leases',
    };
    const allowedSet = allowed;
    final violations = catalogWrites.difference(allowedSet);
    expect(
      violations,
      isEmpty,
      reason: 'v2 路径对其余 13 张 catalog 表零写入（B2 守卫）: $violations',
    );
  });

  test('zero-write guard: course.db writes touch only the view table',
      () async {
    final (sourceId, _) = seedStagedSource();
    await OfficialAnkiV2ImportService(
      catalog: catalog,
      paths: paths,
      course: course,
      engine: engine,
    ).commit(
      sourceId: sourceId,
      packagePath: 'pkg.apkg',
      displayName: 'Basics',
    );

    final violations = courseWrites.difference({'anki_course_tree_view'});
    expect(
      violations,
      isEmpty,
      reason: 'v2 路径对 course.db 旧 anki 表零写入（守卫）: $violations',
    );

    // 旧表在 v24 中已被彻底删除（含 onCreate 侧：新装库不得经
    // `_ensureAnkiCanonicalV2` 复活 v1 投影表——新装/升级 schema 一致）。
    final existingTables = (await course.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ).get()).map((row) => row.read<String>('name')).toSet();
    for (final table in const [
      'official_anki_projection_index',
      'official_anki_projection_manifest',
      'anki_course_card_placements',
      'anki_card_presentations',
      'anki_course_sources',
      'anki_import_jobs',
      'anki_decks',
      'anki_practice_projections',
      'anki_import_issues',
    ]) {
      expect(existingTables.contains(table), isFalse, reason: '$table 必须已被彻底删除');
    }
  });

  test('idempotent replay: re-commit of an active v2 source re-imports nothing',
      () async {
    final (sourceId, _) = seedStagedSource();
    final service = OfficialAnkiV2ImportService(
      catalog: catalog,
      paths: paths,
      course: course,
      engine: engine,
    );
    await service.commit(
      sourceId: sourceId,
      packagePath: 'pkg.apkg',
      displayName: 'Basics',
    );
    final importsAfterFirst = engine.importCount;
    final configWritesAfterFirst = engine.setConfigCalls;

    final replay = await service.commit(
      sourceId: sourceId,
      packagePath: 'pkg.apkg',
      displayName: 'Basics',
    );

    expect(engine.importCount, importsAfterFirst,
        reason: '已 active 的 v2 source 不得重复导入');
    expect(replay.cardCount, 4, reason: '重放按账本/视图汇报');
    expect(
      await OfficialAnkiV2ViewStore(course).cardCountForSource(sourceId),
      4,
      reason: '视图幂等重建',
    );
    // 配置区可能被重写同值（no-op 语义），但绝不能少。
    expect(engine.setConfigCalls, greaterThanOrEqualTo(configWritesAfterFirst));
  });

  test('card-index segment replays idempotently (ADR 0044 R1.5)', () async {
    final (sourceId, attemptId) = seedStagedSource();
    await OfficialAnkiV2ImportService(
      catalog: catalog,
      paths: paths,
      course: course,
      engine: engine,
    ).commit(
      sourceId: sourceId,
      packagePath: 'pkg.apkg',
      displayName: 'Basics',
    );
    final sources = OfficialAnkiSourceDao(catalog);
    expect(sources.cardCount(sourceId), 4);

    // 强杀重放语义：段中途被杀后按意图重跑同一段（worker 与 inline 共享
    // officialAnkiV2RunCardIndex），upsert 不得产生重复行。
    final replayed = await officialAnkiV2RunCardIndex(
      sources: sources,
      attempts: OfficialAnkiImportAttemptDao(catalog),
      engine: engine,
      attemptId: attemptId,
      sourceId: sourceId,
    );
    expect(replayed, 4);
    expect(sources.cardCount(sourceId), 4, reason: '重放不得产生重复所有权行');
  });

  test('mapping decision survives a corrupted config read (K10 resilience)',
      () async {
    final (sourceId, _) = seedStagedSource();
    await OfficialAnkiV2ImportService(
      catalog: catalog,
      paths: paths,
      course: course,
      engine: engine,
    ).commit(
      sourceId: sourceId,
      packagePath: 'pkg.apkg',
      displayName: 'Basics',
    );
    // 配置区损坏（值不再可解析）→ decode 得 null，不抛错（rslib 语义）。
    engine.configStore['turna.import.mapping.$sourceId'] = 'not-a-map';
    final decision = await OfficialAnkiV2DecisionStore(engine)
        .readImportMapping(sourceId);
    expect(decision, isNull);
  });
}
