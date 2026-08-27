import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';

import '../../helpers/in_memory_course_db.dart';

// The publish path must carry imported history into the seed: cards the
// collection proves already studied (reps>=1) land introduced, fresh cards
// land unintroduced — through the same replaceOfficialProjection entry the
// import wizard and source regeneration use.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late AnkiUnificationDao dao;

  setUp(() async {
    db = CourseDatabase(NativeDatabase.memory());
    dao = AnkiUnificationDao(db);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<CourseDatabase>(db);
    GetIt.instance.registerSingleton<AnkiUnificationDao>(dao);
    GetIt.instance.registerSingleton(CardIntroductionStore(dao: dao));
  });

  tearDown(() async {
    await GetIt.instance.reset();
    await db.close();
  });

  OfficialAnkiProjectedItem item(int cardId) => OfficialAnkiProjectedItem(
        kind: OfficialAnkiProjectionKind.showWord,
        cardId: cardId,
        wordId: 'official-anki-profile-default-01-c$cardId',
        sectionId: 'official-anki-src-hist-s1',
        unitId: 'official-anki-src-hist-u1',
        lessonId: 'official-anki-src-hist-l1-p1',
        sectionName: 'S',
        unitName: 'U',
        lessonName: 'L',
        payload: const <String, Object?>{},
        sourceFingerprint: 'fp',
      );

  test('publish seeds imported-history cards as introduced', () async {
    await OfficialAnkiCourseProjectionStore(db).replaceOfficialProjection(
      sourceId: 'src-hist',
      plan: OfficialAnkiProjectionPlan(
        items: [item(101), item(102)],
        issues: const [],
      ),
      studiedCardIds: const {101},
    );

    CanonicalCardKey keyFor(int cardId) => CanonicalCardKey(
          backend: AnkiBackendKind.official,
          profileId: 'profile-default-01',
          sourceId: 'src-hist',
          cardId: cardId,
        );

    final studied = await dao.introductionState(
      courseId: 'official-anki-src-hist',
      key: keyFor(101),
    );
    expect(studied.status, CardIntroductionStatus.introduced);
    expect(studied.introducedBy, CardIntroducedBy.importedHistory);

    final fresh = await dao.introductionState(
      courseId: 'official-anki-src-hist',
      key: keyFor(102),
    );
    expect(fresh.status, CardIntroductionStatus.unintroduced);

    expect(
      GetIt.instance<CardIntroductionStore>()
          .introducedCardIdsForSource('src-hist'),
      {101},
    );
  });
}
