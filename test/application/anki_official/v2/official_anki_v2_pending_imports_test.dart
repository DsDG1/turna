import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_pending_imports.dart';
import 'package:turna/data/course_database.dart';

import '../../../helpers/in_memory_course_db.dart';

/// step4.md B4（K1）：staging census v2 的完整性分级。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late OfficialAnkiDatabase catalog;
  late CourseDatabase course;
  late Directory stagingRoot;

  setUp(() {
    catalog = OfficialAnkiDatabase.memory();
    course = CourseDatabase(NativeDatabase.memory());
    stagingRoot =
        Directory.systemTemp.createTempSync('turna-v2-census-');
  });

  tearDown(() {
    catalog.close();
    course.close();
    try {
      stagingRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  void seedV2Attempt({
    required String sourceId,
    required String attemptId,
    required String phase,
    String? stagingPath,
  }) {
    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: sourceId,
      profileId: 'profile-v2-census',
      sourceHash: 'hash-$sourceId',
      sourceSize: 10,
      displayName: 'P',
      state: 'preview_ready',
      backendCommit: 'pending',
      nowMillis: 1,
    );
    sources.markChainV2(sourceId: sourceId, nowMillis: 1);
    OfficialAnkiImportAttemptDao(catalog).insert(
      attemptId: attemptId,
      sourceId: sourceId,
      requestId: 'req-$attemptId',
      state: 'preview_ready',
      nowMillis: 1,
      phase: phase,
      stagingPath: stagingPath,
    );
  }

  test('resumable: staging dir with intact collection.anki2', () async {
    File(p.join(stagingRoot.path, 'collection.anki2')).writeAsBytesSync([1]);
    seedV2Attempt(
      sourceId: 'src-a',
      attemptId: 'att-a',
      phase: 'preview_ready',
      stagingPath: stagingRoot.path,
    );
    final pending = OfficialAnkiV2PendingImports.list(catalog);
    expect(pending, hasLength(1));
    expect(pending.single.verdict,
        OfficialAnkiV2PendingImportVerdict.resumable);
    expect(pending.single.phase, 'preview_ready');
  });

  test('rebuildStaging: dir exists but collection missing', () async {
    seedV2Attempt(
      sourceId: 'src-b',
      attemptId: 'att-b',
      phase: 'staging_importing',
      stagingPath: stagingRoot.path, // 目录在、库缺
    );
    final pending = OfficialAnkiV2PendingImports.list(catalog);
    expect(pending.single.verdict,
        OfficialAnkiV2PendingImportVerdict.rebuildStaging);
  });

  test('gone: staging directory was wiped', () async {
    final deleted = Directory('${stagingRoot.path}/gone')
      ..createSync(recursive: true);
    deleted.deleteSync(recursive: true);
    seedV2Attempt(
      sourceId: 'src-c',
      attemptId: 'att-c',
      phase: 'preview_ready',
      stagingPath: '${stagingRoot.path}/gone',
    );
    final pending = OfficialAnkiV2PendingImports.list(catalog);
    expect(pending.single.verdict, OfficialAnkiV2PendingImportVerdict.gone);
  });

  test('v1-chain attempts are not listed by the v2 census', () async {
    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: 'src-v1',
      profileId: 'profile-v2-census',
      sourceHash: 'hash-v1',
      sourceSize: 10,
      displayName: 'V1',
      state: 'preview_ready',
      backendCommit: 'pending',
      nowMillis: 1,
    );
    catalog.handle.execute("UPDATE anki_sources SET chain = 'v1' WHERE source_id = 'src-v1'");
    OfficialAnkiImportAttemptDao(catalog).insert(
      attemptId: 'att-v1',
      sourceId: 'src-v1',
      requestId: 'req-v1',
      state: 'preview_ready',
      nowMillis: 1,
      phase: 'preview_ready',
      stagingPath: stagingRoot.path,
    );
    expect(OfficialAnkiV2PendingImports.list(catalog), isEmpty,
        reason: 'v1 的 pending imports 语义不改（B4：v2 语义不改 v1 行为）');
  });
}


