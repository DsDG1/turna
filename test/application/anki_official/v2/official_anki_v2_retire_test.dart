import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_retire_service.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_store.dart';
import 'package:turna/data/course_database.dart';

import '../../../helpers/in_memory_course_db.dart';

/// step4.md B5（D6/K6）：retiring 删除序列逐段幂等 + 强杀收敛。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late OfficialAnkiDatabase catalog;
  late CourseDatabase course;
  late FakeOfficialAnkiEngine engine;
  late Directory root;
  late OfficialAnkiPaths paths;

  setUp(() {
    root = Directory.systemTemp.createTempSync('turna-v2-retire-');
    catalog = OfficialAnkiDatabase.memory();
    course = CourseDatabase(NativeDatabase.memory());
    engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: 'pkg.apkg', notes: 2, cards: 2);
    engine.deckTree = const [
      OfficialAnkiDeckNode(deckId: 10, name: 'Deck A', level: 0),
    ];
    paths = OfficialAnkiPaths(
      profileId: 'profile-v2-retire',
      profileRoot: Directory(p.join(root.path, 'live'))
        ..createSync(recursive: true),
    );
  });

  tearDown(() {
    catalog.close();
    course.close();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 导入完成态的 v2 source（含所有权清单与视图行）。
  Future<String> seedActiveV2Source({String sourceId = 'src-r1'}) async {
    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: sourceId,
      profileId: paths.profileId,
      sourceHash: 'hash-$sourceId',
      sourceSize: 10,
      displayName: 'R',
      state: 'active',
      backendCommit: 'pending',
      nowMillis: 1,
    );
    sources.markChainV2(sourceId: sourceId, nowMillis: 1);
    sources.upsertCardBatch(
      sourceId: sourceId,
      cards: [
        const OfficialAnkiCardDescriptor(
            cardId: 1, noteId: 1, deckId: 10, templateOrd: 0, notetypeId: 1),
        const OfficialAnkiCardDescriptor(
            cardId: 2, noteId: 2, deckId: 10, templateOrd: 0, notetypeId: 1),
      ],
    );
    // 引擎侧同卡存在（模拟 live Collection 里的两行）。
    engine.seedPackage(packagePath: 'pkg.apkg', notes: 2, cards: 2);
    await OfficialAnkiV2ViewStore(course).replaceAll(
      rows: const [],
      rebuiltAtMillis: 0,
    );
    return sourceId;
  }

  OfficialAnkiV2RetireService service({int deleteChunk = 5000}) =>
      OfficialAnkiV2RetireService(
        catalog: catalog,
        paths: paths,
        course: course,
        engine: engine,
        deleteChunk: deleteChunk,
      );

  test('① beginRetire: single ledger transaction + immediate invisibility',
      () async {
    final sourceId = await seedActiveV2Source();
    // 预置视图行（用户已见课程）。
    await OfficialAnkiV2ViewStore(course).replaceAll(
      rows: [
        OfficialAnkiV2ViewRow(
          sourceId: sourceId,
          cardId: 1,
          noteId: 1,
          deckId: 10,
          wordId: 'w-1',
          sectionKey: 'Deck A',
          sectionId: 'official-anki-$sourceId-s1',
          unitId: 'official-anki-$sourceId-u1',
          lessonId: 'official-anki-$sourceId-l1',
          lessonKey: 'Deck A',
          presentationKind: 'showWord',
          sourceHash: 'hash-$sourceId',
        ),
      ],
      rebuiltAtMillis: 1,
    );
    final jobId = await service().beginRetire(sourceId: sourceId);

    final source = OfficialAnkiSourceDao(catalog).findById(sourceId);
    expect(source!.state, 'retiring');
    expect(jobId, isNotEmpty);
    final jobs = OfficialAnkiMaintenanceJobDao(catalog)
        .pending(profileId: paths.profileId);
    expect(jobs.any((j) => j['kind'] == 'v2_source_delete'), isTrue,
        reason: '删除 job 已入队（强杀后由它续跑）');
    expect(
      await OfficialAnkiV2ViewStore(course).cardCountForSource(sourceId),
      0,
      reason: 'K6：用户视角即刻移除（视图定向删行）',
    );

    // 幂等：重复 begin 不炸、复用 pending job。
    final jobId2 = await service().beginRetire(sourceId: sourceId);
    expect(jobId2, jobId);
    expect(
        OfficialAnkiSourceDao(catalog).findById(sourceId)!.state, 'retiring');
  });

  test('① beginRetire: post-commit view-row failure defers instead of failing',
      () async {
    final sourceId = await seedActiveV2Source();
    // 预置视图行（用户已见课程）。
    await OfficialAnkiV2ViewStore(course).replaceAll(
      rows: [
        OfficialAnkiV2ViewRow(
          sourceId: sourceId,
          cardId: 1,
          noteId: 1,
          deckId: 10,
          wordId: 'w-1',
          sectionKey: 'Deck A',
          sectionId: 'official-anki-$sourceId-s1',
          unitId: 'official-anki-$sourceId-u1',
          lessonId: 'official-anki-$sourceId-l1',
          lessonKey: 'Deck A',
          presentationKind: 'showWord',
          sourceHash: 'hash-$sourceId',
        ),
      ],
      rebuiltAtMillis: 1,
    );
    // 模拟 COMMIT 之后的瞬时存储错误（busy/locked）：让视图定向删行必败。
    await course.customStatement('DROP TABLE anki_course_tree_view');

    final jobId = await service().beginRetire(sourceId: sourceId);

    expect(jobId, isNotEmpty,
        reason: '视图删行失败不得把已提交的移除报成失败（UI 会一边显示'
            '已移除、一边提示「移除未完成」）');
    expect(
      OfficialAnkiSourceDao(catalog).findById(sourceId)!.state,
      'retiring',
      reason: '账本事务已提交且不得回滚（旧实现在 COMMIT 后执行 ROLLBACK '
          '会再抛错并掩盖原始异常）',
    );
    expect(
      OfficialAnkiMaintenanceJobDao(catalog)
          .pending(profileId: paths.profileId)
          .any((j) => j['kind'] == 'v2_source_delete'),
      isTrue,
      reason: '删除 job 已入队，残留视图行由 job ③ 的视图重建收敛',
    );
  });

  test('②③④ full job: engine delete + 5-table final delete + GC jobs',
      () async {
    final sourceId = await seedActiveV2Source();
    await service().beginRetire(sourceId: sourceId);

    final completed = await service().runRetireJob(sourceId: sourceId);
    expect(completed, isTrue);

    // 引擎里的卡真的删了。
    expect(engine.cards, isEmpty);
    // 账本行终删（sources/cards/attempts 全无）。
    expect(OfficialAnkiSourceDao(catalog).findById(sourceId), isNull);
    expect(OfficialAnkiSourceDao(catalog).cardCount(sourceId), 0);
    // 配置区映射决策清理。
    expect(
      engine.configStore.containsKey('turna.import.mapping.$sourceId'),
      isFalse,
    );
    // ④ 字节回收 jobs 入队。
    final kinds = OfficialAnkiMaintenanceJobDao(catalog)
        .pending(profileId: paths.profileId)
        .map((j) => j['kind'])
        .toSet();
    expect(kinds, containsAll(['media_gc', 'compact_collection']));
  });

  test('segment idempotency: re-running the job after completion converges',
      () async {
    final sourceId = await seedActiveV2Source();
    await service().beginRetire(sourceId: sourceId);
    expect(await service().runRetireJob(sourceId: sourceId), isTrue);
    // 模拟「重启后续跑」：job 再跑一遍（source 已不存在）。
    expect(await service().runRetireJob(sourceId: sourceId), isTrue);
    expect(engine.deleteCardsCallCount <= 2, isTrue,
        reason: '终删后不再反复引擎调用（第二遍 source 缺席直接收敛）');
  });

  test('engine unavailable: job defers, source stays retiring (K6 no orphans)',
      () async {
    final sourceId = await seedActiveV2Source();
    await service().beginRetire(sourceId: sourceId);

    final completed = await OfficialAnkiV2RetireService(
      catalog: catalog,
      paths: paths,
      course: course,
      engine: null,
    ).runRetireJob(sourceId: sourceId);
    expect(completed, isFalse, reason: '引擎缺席 → job 留队重跑');
    expect(OfficialAnkiSourceDao(catalog).findById(sourceId)!.state, 'retiring',
        reason: '不产生无主且不可见的卡：账本行保留到引擎删除完成');
    expect(engine.cards, isNotEmpty, reason: '引擎里的卡未被误删');
  });

  test('maintenance runner drives v2_source_delete to completion', () async {
    final sourceId = await seedActiveV2Source();
    await service().beginRetire(sourceId: sourceId);

    final runner = OfficialAnkiMaintenanceRunner(
      catalog: catalog,
      paths: paths,
      engine: engine,
      course: course,
    );
    final completed = await runner.runPending(profileId: paths.profileId);
    expect(completed, greaterThanOrEqualTo(1));
    expect(OfficialAnkiSourceDao(catalog).findById(sourceId), isNull,
        reason: 'runPending 把 retiring 序列推进到终删');
    // 重快照循环：retire 第④步入队的 media_gc/compact_* 必须在同一把
    // lease、同一次 runPending 里被消费，而不是留到下次启动。
    expect(
      OfficialAnkiMaintenanceJobDao(catalog)
          .pending(profileId: paths.profileId),
      isEmpty,
      reason: 'retire 入队的回收 job 应同轮 drain 完毕',
    );
  });

  test('maintenance runner keeps v2_source_delete alive without engine',
      () async {
    final sourceId = await seedActiveV2Source();
    await service().beginRetire(sourceId: sourceId);

    final runner = OfficialAnkiMaintenanceRunner(
      catalog: catalog,
      paths: paths,
      engine: null,
      course: course,
    );
    await runner.runPending(profileId: paths.profileId);
    final pending = OfficialAnkiMaintenanceJobDao(catalog)
        .pending(profileId: paths.profileId)
        .where((j) => j['kind'] == 'v2_source_delete')
        .toList();
    expect(pending, isNotEmpty,
        reason: '引擎缺席 → job 进 retry_wait 保活（K6 收敛由重跑保证）');
    expect(pending.first['attempt_count'], greaterThan(0));
  });

  test('engine delete pages ownership ids without loading the full list',
      () async {
    const sourceId = 'src-paged';
    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: sourceId,
      profileId: paths.profileId,
      sourceHash: 'hash-$sourceId',
      sourceSize: 10,
      displayName: 'R',
      state: 'active',
      backendCommit: 'pending',
      nowMillis: 1,
    );
    sources.markChainV2(sourceId: sourceId, nowMillis: 1);
    sources.upsertCardBatch(
      sourceId: sourceId,
      cards: [
        for (var i = 1; i <= 5; i++)
          OfficialAnkiCardDescriptor(
            cardId: i,
            noteId: i,
            deckId: 10,
            templateOrd: 0,
            notetypeId: 1,
          ),
      ],
    );
    engine.seedPackage(packagePath: 'pkg.apkg', notes: 5, cards: 5);

    await service(deleteChunk: 2).beginRetire(sourceId: sourceId);
    expect(
        await service(deleteChunk: 2).runRetireJob(sourceId: sourceId), isTrue);
    expect(engine.cards, isEmpty);
    expect(engine.deleteCardsCallCount, 3,
        reason: '5 ids / chunk 2 = 3 batches');
    expect(OfficialAnkiSourceDao(catalog).findById(sourceId), isNull);
  });
}
