import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_unowned_card_reclaimer.dart';

void main() {
  late OfficialAnkiDatabase catalog;
  late FakeOfficialAnkiEngine engine;
  late Directory root;
  late OfficialAnkiPaths paths;
  late OfficialAnkiSourceDao sources;

  setUp(() async {
    catalog = OfficialAnkiDatabase.memory();
    sources = OfficialAnkiSourceDao(catalog);
    engine = FakeOfficialAnkiEngine();
    root = Directory.systemTemp.createTempSync('turna-v2-ghost-');
    paths = OfficialAnkiPaths(
      profileId: 'profile-v2-ghost',
      profileRoot: Directory(p.join(root.path, 'live'))..createSync(recursive: true),
    );
    await engine.openProfile(paths);
    engine.cards[1] = const OfficialAnkiCardDescriptor(
      cardId: 1,
      noteId: 10,
      deckId: 1,
      templateOrd: 0,
      noteGuid: 'owned',
      notetypeId: 1,
    );
    engine.cards[2] = const OfficialAnkiCardDescriptor(
      cardId: 2,
      noteId: 20,
      deckId: 1,
      templateOrd: 0,
      noteGuid: 'ghost',
      notetypeId: 1,
    );
    engine.cardsByNote[10] = [1];
    engine.cardsByNote[20] = [2];
  });

  tearDown(() {
    catalog.close();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('deletes collection cards not owned by active/retiring sources', () async {
    sources.upsertSource(
      sourceId: 'src-live',
      profileId: paths.profileId,
      sourceHash: 'h-live',
      sourceSize: 1,
      displayName: 'Live',
      state: 'active',
      backendCommit: 't',
      nowMillis: 1,
    );
    sources.markChainV2(sourceId: 'src-live', nowMillis: 1);
    sources.upsertCardBatch(
      sourceId: 'src-live',
      cards: [engine.cards[1]!],
    );

    final deleted = await OfficialAnkiV2UnownedCardReclaimer(
      catalog: catalog,
      paths: paths,
      engine: engine,
    ).purge();

    expect(deleted, 1);
    expect(engine.cards.keys, [1]);
    expect(engine.deleteCardsCallCount, 1);
    final jobs = OfficialAnkiMaintenanceJobDao(catalog)
        .pending(profileId: paths.profileId)
        .map((row) => row['kind'])
        .toSet();
    expect(jobs, containsAll(['media_gc', 'compact_collection']));
  });

  test('startup recovery abandons v2 committing and purges ghosts', () async {
    sources.upsertSource(
      sourceId: 'src-live',
      profileId: paths.profileId,
      sourceHash: 'h-live',
      sourceSize: 1,
      displayName: 'Live',
      state: 'active',
      backendCommit: 't',
      nowMillis: 1,
    );
    sources.markChainV2(sourceId: 'src-live', nowMillis: 1);
    sources.upsertCardBatch(
      sourceId: 'src-live',
      cards: [engine.cards[1]!],
    );
    sources.upsertSource(
      sourceId: 'src-kill',
      profileId: paths.profileId,
      sourceHash: 'h-kill',
      sourceSize: 1,
      displayName: 'Killed',
      state: 'preview_ready',
      backendCommit: 'pending',
      nowMillis: 2,
    );
    sources.markChainV2(sourceId: 'src-kill', nowMillis: 2);
    OfficialAnkiImportAttemptDao(catalog).insert(
      attemptId: 'att-kill',
      sourceId: 'src-kill',
      requestId: 'req-kill',
      state: 'preview_ready',
      nowMillis: 2,
      phase: OfficialAnkiAttemptPhase.committing,
    );

    // K2 中断恢复（v2 committing）：丢弃账本 + 回收 collection 幽灵卡。
    // 编排器删除后，中断导入的生产恢复路径 = saga.cancelSource（pending
    // banner 手动丢弃走同一方法）。
    await OfficialAnkiImportSaga(
      sources: sources,
      attempts: OfficialAnkiImportAttemptDao(catalog),
      paths: paths,
      liveEngine: engine,
    ).cancelSource('src-kill');

    final attempts = OfficialAnkiImportAttemptDao(catalog);
    expect(attempts.find('att-kill'), isNull, reason: '账本随 source 终删');
    expect(attempts.unfinished(), isEmpty);
    expect(sources.findById('src-kill'), isNull);
    expect(engine.cards.keys, [1]);
    expect(sources.findById('src-live'), isNotNull);
  });
}
