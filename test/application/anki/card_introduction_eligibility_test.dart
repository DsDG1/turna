import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/application/anki/card_introduction_store.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_snapshot_builder.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_update.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const eligibility = CardIntroductionEligibility();

  setUp(() {
    CardIntroductionStore.debugOverride = CardIntroductionStore();
    OfficialFormalDueRepository.instance.resetForTest();
  });

  tearDown(() {
    CardIntroductionStore.debugOverride = null;
  });

  group('pure eligibility', () {
    test('unlearned new cards are not formally eligible', () {
      expect(
        eligibility.isFormallyEligible(stored: null, reps: 0),
        isFalse,
      );
      expect(
        eligibility.isFormallyEligible(
          stored: CardIntroductionStatus.unintroduced,
          reps: 0,
        ),
        isFalse,
      );
    });

    test('imported history and course introduction are eligible', () {
      expect(
        eligibility.isFormallyEligible(stored: null, reps: 3),
        isTrue,
      );
      expect(
        eligibility.isFormallyEligible(
          stored: CardIntroductionStatus.introduced,
          reps: 0,
        ),
        isTrue,
      );
      expect(
        eligibility.isFormallyEligible(
          stored: CardIntroductionStatus.retired,
          reps: 9,
        ),
        isFalse,
      );
    });

    test('formal due is 0 when nothing is introduced', () {
      expect(
        eligibility.formalDueCount(schedulerDue: 20, introducedCount: 0),
        0,
      );
      expect(
        eligibility.formalDueCount(schedulerDue: 20, introducedCount: 3),
        3,
      );
      expect(
        eligibility.formalDueCount(schedulerDue: 2, introducedCount: 8),
        2,
      );
    });
  });

  group('official session filter', () {
    const flags = OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
      renderer: true,
      scheduler: true,
    );

    test('empty allowed set means no unintroduced new cards are shown',
        () async {
      final fake = FakeOfficialAnkiEngine();
      fake.seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
      final session = OfficialReviewSession(
        engine: fake,
        flags: flags,
        allowedCardIds: const {},
      );
      await session.openDeck(1);
      expect(session.current, isNull);
      expect(session.phase, OfficialReviewPhase.completed);
    });
  });

  group('official home due display', () {
    test('scheduler due of 20 with 0 introduced displays 0', () {
      _commitSource(
        'src',
        schedulerDue: {for (var i = 1; i <= 20; i++) i},
        rawDue: 20,
      );
      final repo = OfficialFormalDueRepository.instance;
      expect(repo.formalOfficialDueForImport('src'), 0);
      expect(repo.snapshot.introducedOfficialDue, 0);
      expect(repo.snapshot.unintroducedOfficialDue, 20);
    });

    test('scheduler due of 20 with 3 introduced displays 3', () async {
      final store = CardIntroductionStore.debugOverride!;
      await store.markFromLesson(
        wordId: 'official-anki-src-c1',
        lessonId: 'official-anki-src-l0123456789ab-p1',
      );
      await store.markFromLesson(
        wordId: 'official-anki-src-c2',
        lessonId: 'official-anki-src-l0123456789ab-p1',
      );
      await store.markFromLesson(
        wordId: 'official-anki-src-c3',
        lessonId: 'official-anki-src-l0123456789ab-p1',
      );
      _commitSource(
        'src',
        schedulerDue: {for (var i = 1; i <= 20; i++) i},
        placement: {for (var i = 1; i <= 20; i++) i},
        rawDue: 20,
      );
      final repo = OfficialFormalDueRepository.instance;
      expect(repo.formalOfficialDueForImport('src'), 3);
      expect(repo.snapshot.unintroducedOfficialDue, 17);
    });
  });
}


void _commitSource(
  String importId, {
  required Set<int> schedulerDue,
  Set<int> placement = const {},
  int rawDue = 0,
}) {
  OfficialFormalDueRepository.instance.commit(
    OfficialFormalDueUpdate(
      bySource: {
        importId: buildFormalDuePerSource(
          importId: importId,
          schedulerDueCardIds: schedulerDue,
          schedulerDueSynced: true,
          activePlacementCardIds: placement,
          suspendedCardIds: const {},
          buriedCardIds: const {},
          retiredCardIds: const {},
        ),
      },
      rawDueBySource: {importId: rawDue},
      turnaDue: 0,
      unintroducedNew: 0,
    ),
    basedOnGeneration: OfficialFormalDueRepository.instance.generation,
  );
}
