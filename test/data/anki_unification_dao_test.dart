import 'package:flutter_test/flutter_test.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';

import '../helpers/in_memory_course_db.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('schema v18 introduction persist and unique active presentation',
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

    await dao.insertActivePlacement(
      placementId: 'pl-9',
      courseId: 'c1',
      profileId: 'p',
      key: key,
      sectionId: 's',
      unitId: 'u',
      lessonId: 'l1',
      order: 0,
      sourceFingerprint: 'fp',
    );
    await dao.insertActivePresentation(
      courseId: 'c1',
      key: key,
      kind: 'flip',
      payloadJson: '{"front":"a","back":"b"}',
      sourceFingerprint: 'fp',
    );

    await expectLater(
      dao.insertActivePresentation(
        courseId: 'c1',
        key: key,
        kind: 'multipleChoice',
        payloadJson: '{}',
        sourceFingerprint: 'fp',
      ),
      throwsA(isA<Object>()),
    );

    await expectLater(
      dao.insertActivePlacement(
        placementId: 'pl-9-dup',
        courseId: 'c1',
        profileId: 'p',
        key: key,
        sectionId: 's',
        unitId: 'u',
        lessonId: 'l2',
        order: 1,
        sourceFingerprint: 'fp',
      ),
      throwsA(isA<Object>()),
    );

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
      [
        'anki_card_introduction_states',
        'anki_card_presentations',
        'anki_course_card_placements',
        'anki_course_sources',
        'anki_import_jobs',
        'study_product_events',
      ],
    );
  });
}
