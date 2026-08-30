// P5F-41: one-shot re-anchor of official placements onto the projection
// index.

// Package imports:
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki_official/migration/official_first_reanchor.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

OfficialAnkiProjectedItem _item(String sourceId, int cardId) =>
    OfficialAnkiProjectedItem(
      kind: OfficialAnkiProjectionKind.showWord,
      cardId: cardId,
      wordId: 'official-anki-profile-default-01-c$cardId',
      sectionId: 'official-anki-$sourceId-s1',
      unitId: 'official-anki-$sourceId-u1',
      lessonId: 'official-anki-$sourceId-l1-p1',
      sectionName: 'S',
      unitName: 'U',
      lessonName: 'L',
      payload: const <String, Object?>{},
      sourceFingerprint: 'fp',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late OfficialAnkiDatabase catalog;
  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(preferences);
    db = CourseDatabase(NativeDatabase.memory());
    catalog = OfficialAnkiDatabase.memory();
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<CourseDatabase>(db);
    GetIt.instance.registerSingleton<AnkiUnificationDao>(AnkiUnificationDao(db));
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    OfficialAnkiCompositionRoot.locatorPaths = null;
    OfficialFirstReanchor.debugForceRun = true;
  });

  tearDown(() async {
    OfficialFirstReanchor.debugForceRun = false;
    OfficialAnkiCompositionRoot.readOnlyCatalog = null;
    await GetIt.instance.reset();
    await db.close();
    catalog.close();
  });

  test('re-anchors active sources with a manifest, skips the rest', () async {
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src-anchored',
      profileId: 'profile-default-01',
      sourceHash: 'hash-a',
      sourceSize: 1,
      displayName: 'a',
      state: 'active',
      backendCommit: 't',
      nowMillis: 1,
    );
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src-noprojection',
      profileId: 'profile-default-01',
      sourceHash: 'hash-b',
      sourceSize: 1,
      displayName: 'b',
      state: 'active',
      backendCommit: 't',
      nowMillis: 1,
    );
    await OfficialAnkiCourseProjectionStore(db).replaceOfficialProjection(
      sourceId: 'src-anchored',
      plan: OfficialAnkiProjectionPlan(
        items: [_item('src-anchored', 1), _item('src-anchored', 2)],
        issues: const [],
      ),
    );

    final published = await OfficialFirstReanchor().runIfNeeded(prefs);
    expect(published, 2, reason: 'one placement per projected card');
    final rows = await db.customSelect(
      "SELECT COUNT(*) AS n FROM anki_course_card_placements "
      "WHERE source_id = 'src-anchored'",
    ).getSingle();
    expect(rows.read<int>('n'), 2);
    final unanchored = await db.customSelect(
      "SELECT COUNT(*) AS n FROM anki_course_card_placements "
      "WHERE source_id = 'src-noprojection'",
    ).getSingle();
    expect(unanchored.read<int>('n'), 0,
        reason: 'dual-write era sources without a projection keep their '
            'existing rows untouched');

    // The pref marks the task done: a normal second run is a no-op.
    OfficialFirstReanchor.debugForceRun = false;
    final again = await OfficialFirstReanchor().runIfNeeded(prefs);
    expect(again, 0);
  });
}
