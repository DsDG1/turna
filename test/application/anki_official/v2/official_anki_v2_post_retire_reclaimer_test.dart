import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_post_retire_reclaimer.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_retire_service.dart';
import 'package:turna/data/course_database.dart';

import '../../../helpers/in_memory_course_db.dart';

/// 删除后字节回收：retire 只入队回收 job，回收器负责同链路消费；
/// 账本清空时 ghost 文件（backups/collection）随删除一并清掉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late OfficialAnkiDatabase catalog;
  late CourseDatabase course;
  late FakeOfficialAnkiEngine engine;
  late Directory root;
  late OfficialAnkiPaths paths;

  setUp(() {
    root = Directory.systemTemp.createTempSync('turna-post-retire-');
    catalog = OfficialAnkiDatabase.memory();
    course = CourseDatabase(NativeDatabase.memory());
    engine = FakeOfficialAnkiEngine();
    paths = OfficialAnkiPaths(
      profileId: 'profile-post-retire',
      profileRoot: Directory(p.join(root.path, 'live'))
        ..createSync(recursive: true),
    );
    // Ghost 文件：retire 序列不触碰、只有 purge 会删的表面。
    File(p.join(paths.profileRoot.path, 'collection.anki2'))
        .writeAsBytesSync([1, 2, 3, 4]);
    Directory(p.join(paths.profileRoot.path, 'backups')).createSync();
    File(p.join(paths.profileRoot.path, 'backups', 'b.zip'))
        .writeAsBytesSync([9]);
  });

  tearDown(() {
    catalog.close();
    course.close();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> seedActiveV2Source(String sourceId) async {
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
      ],
    );
  }

  /// [withEngine] 原样透传（含 null）：测「引擎缺席」时不能回退默认引擎。
  OfficialAnkiV2RetireService retireService({OfficialAnkiEngine? withEngine}) =>
      OfficialAnkiV2RetireService(
        catalog: catalog,
        paths: paths,
        course: course,
        engine: withEngine,
      );

  OfficialAnkiV2PostRetireReclaimer reclaimer(
          {OfficialAnkiEngine? withEngine}) =>
      OfficialAnkiV2PostRetireReclaimer(
        catalog: catalog,
        paths: paths,
        engine: withEngine,
        course: course,
      );

  test('drains the reclamation jobs retire enqueued', () async {
    await seedActiveV2Source('src-r1');
    engine.seedPackage(packagePath: 'pkg.apkg', notes: 1, cards: 1);
    final retire = retireService(withEngine: engine);
    await retire.beginRetire(sourceId: 'src-r1');
    await retire.runRetireJob(sourceId: 'src-r1');

    await reclaimer(withEngine: engine).run();

    final jobs = OfficialAnkiMaintenanceJobDao(catalog);
    expect(
      jobs.pending(profileId: paths.profileId),
      isEmpty,
      reason: 'media_gc/compact_* 应被回收器当场消费，而非等下次启动',
    );
    expect(engine.gcCalls, greaterThan(0));
    expect(engine.compactCalls, greaterThan(0));
  });

  test('purges ghost files when the retire emptied the ledger', () async {
    await seedActiveV2Source('src-r1');
    engine.seedPackage(packagePath: 'pkg.apkg', notes: 1, cards: 1);
    final retire = retireService(withEngine: engine);
    await retire.beginRetire(sourceId: 'src-r1');
    await retire.runRetireJob(sourceId: 'src-r1');

    await reclaimer(withEngine: engine).run();

    expect(
      File(p.join(paths.profileRoot.path, 'collection.anki2')).existsSync(),
      isFalse,
      reason: '最后一个 source 删除后 collection 应被清空重建',
    );
    expect(
      File(p.join(paths.profileRoot.path, 'backups', 'b.zip')).existsSync(),
      isFalse,
      reason: 'backups 目录随 ghost purge 一并清掉',
    );
  });

  test('keeps ghost files while another source still owns the ledger',
      () async {
    await seedActiveV2Source('src-a');
    await seedActiveV2Source('src-b');
    engine.seedPackage(packagePath: 'pkg.apkg', notes: 1, cards: 1);
    final retire = retireService(withEngine: engine);
    await retire.beginRetire(sourceId: 'src-a');
    await retire.runRetireJob(sourceId: 'src-a');

    await reclaimer(withEngine: engine).run();

    expect(
      File(p.join(paths.profileRoot.path, 'collection.anki2')).existsSync(),
      isTrue,
      reason: '账本仍有 src-b，ghost purge 必须 fail-closed',
    );
  });

  test('no engine: nothing drains, jobs stay queued for startup', () async {
    await seedActiveV2Source('src-r1');
    await retireService(withEngine: null).beginRetire(sourceId: 'src-r1');

    await reclaimer(withEngine: null).run();

    expect(
      OfficialAnkiMaintenanceJobDao(catalog)
          .pending(profileId: paths.profileId),
      isNotEmpty,
      reason: '无引擎时回收器应让位，job 留给启动恢复',
    );
    expect(
      File(p.join(paths.profileRoot.path, 'collection.anki2')).existsSync(),
      isTrue,
    );
  });
}
