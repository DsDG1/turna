import 'package:flutter_test/flutter_test.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';

import '../helpers/in_memory_course_db.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('introduction persists and retired unification tables stay deleted',
      () async {
    final db = emptyInMemoryCourseDatabase();
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    final dao = AnkiUnificationDao(db);
    const key = CanonicalCardKey(
      backend: AnkiBackendKind.official,
      profileId: 'p',
      sourceId: 'src',
      cardId: 9,
    );

    await dao.upsertIntroduction(
      courseId: 'c1',
      key: key,
      status: CardIntroductionStatus.introduced,
      introducedBy: CardIntroducedBy.course,
      introducedAt: DateTime.utc(2026, 8, 20),
      firstLessonId: 'l1',
      lastStudiedAt: DateTime.utc(2026, 8, 20),
    );
    final state = await dao.introductionState(courseId: 'c1', key: key);
    expect(state.isIntroduced, isTrue);
    expect(state.introducedBy, CardIntroducedBy.course);
    expect(state.firstLessonId, 'l1');

    // Step 6: the placement/presentation/source-authority tables are gone;
    // only the introduction states and product events remain.
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('anki_course_sources','anki_course_card_placements',"
          "'anki_card_presentations','anki_card_introduction_states',"
          "'study_product_events','anki_import_jobs') ORDER BY name",
        )
        .get();
    expect(
      tables.map((row) => row.read<String>('name')),
      ['anki_card_introduction_states', 'study_product_events'],
    );
  });

  test('introducedCardIdsForSource returns only introduced ids of the source',
      () async {
    final db = emptyInMemoryCourseDatabase();
    addTearDown(db.close);
    final dao = AnkiUnificationDao(db);

    CanonicalCardKey key(int cardId) => CanonicalCardKey(
          backend: AnkiBackendKind.official,
          profileId: 'profile-default-01',
          sourceId: 'src',
          cardId: cardId,
        );

    await dao.upsertIntroduction(
      courseId: 'c1',
      key: key(1),
      status: CardIntroductionStatus.introduced,
      introducedBy: CardIntroducedBy.course,
    );
    await dao.upsertIntroduction(
      courseId: 'c1',
      key: key(2),
      status: CardIntroductionStatus.unintroduced,
    );
    await dao.upsertIntroduction(
      courseId: 'c2',
      key: key(3),
      status: CardIntroductionStatus.retired,
    );

    // The lock reconciler and completion unlocking read this directly —
    // it is the scheduler-lock exemption list, not a UI cache.
    expect(await dao.introducedCardIdsForSource(sourceId: 'src'), {1});
  });
}
