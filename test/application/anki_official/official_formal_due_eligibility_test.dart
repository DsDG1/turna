import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/review/official_study_batch_assembler.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_snapshot_builder.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_update.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_eligibility.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/study_models.dart';

CanonicalCardKey _key(int id) => CanonicalCardKey(
      backend: AnkiBackendKind.official,
      profileId: 'profile-default-01',
      sourceId: 'src-a',
      cardId: id,
    );

FlipCardPresentation _flip(CanonicalCardKey key, String front, String back) {
  return FlipCardPresentation(
    cardKey: key,
    frontText: front,
    backText: back,
    sourceFingerprint: 'fp-${key.cardId}',
  );
}

OfficialReviewQueueCard _queueCard(int cardId) {
  return OfficialReviewQueueCard(
    cardId: cardId,
    noteId: cardId,
    deckId: 1,
    templateOrdinal: 0,
    queueKind: 'review',
    answerToken: 'tok-$cardId',
    labels: const OfficialReviewIntervalLabels(
      again: '1m',
      hard: '10m',
      good: '1d',
      easy: '4d',
    ),
  );
}

void main() {
  group('computeFormalDueCardKeys', () {
    // P1: the scheduler is the gate — locked (unintroduced), suspended and
    // buried cards never reach schedulerDue in the first place, so the
    // Dart formula only scopes placement and drops uninstall remnants.
    test('exact intersection of scheduler due and placement minus retired',
        () {
      final due = computeFormalDueCardKeys(
        officialSchedulerDueCardKeys: {_key(1), _key(2), _key(3), _key(4)},
        activePlacementCardKeys: {_key(1), _key(2), _key(3)},
        retiredCardKeys: {_key(4)},
      );
      expect(due, {_key(1), _key(2), _key(3)});
    });

    test('per-source helper builds the same membership', () {
      final due = computeFormalDueCardKeysForSource(
        sourceId: 'src-a',
        officialSchedulerDueCardIds: {10, 11, 12, 13, 14},
        activePlacementCardIds: {10, 11, 12},
        retiredCardIds: {11},
      );
      expect(due.map((k) => k.cardId).toSet(), {10, 12});
    });

    test('scheduler due alone with no placement is empty', () {
      final due = computeFormalDueCardKeys(
        officialSchedulerDueCardKeys: {_key(1), _key(2)},
        activePlacementCardKeys: const {},
      );
      expect(due, isEmpty);
    });
  });

  group('OfficialStudyBatchAssembler', () {
    test('assembles only scheduler-due ∩ placement cards with presentations',
        () {
      final presentations = <CanonicalCardKey, CardPresentation>{
        _key(1): _flip(_key(1), 'a', 'b'),
        _key(2): _flip(_key(2), 'c', 'd'),
      };
      final items =
          const OfficialStudyBatchAssembler().assembleFromEligibility(
        sourceId: 'src-a',
        courseId: 'course-src-a',
        queueCards: [_queueCard(1), _queueCard(2), _queueCard(3)],
        presentations: presentations,
        activePlacementCardKeys: {_key(1), _key(2), _key(3)},
        retiredCardKeys: {_key(2)},
      );
      expect(items, hasLength(1));
      expect(items.single.cardKey, _key(1));
      expect(items.single.mode, StudyMode.review);
      expect(items.single.ledgerOwner, StudyLedgerOwner.officialAnki);
    });

    test('answering removes card from remaining formal-due set', () {
      var formalDue = {_key(1), _key(2)};
      formalDue = formalDue.difference({_key(1)});
      expect(formalDue, {_key(2)});
      final remaining = const OfficialStudyBatchAssembler().assemble(
        sourceId: 'src-a',
        courseId: 'course-src-a',
        queueCards: [_queueCard(1), _queueCard(2)],
        presentations: {
          _key(1): _flip(_key(1), 'a', 'b'),
          _key(2): _flip(_key(2), 'c', 'd'),
        },
        formalDueCardKeys: formalDue,
      );
      expect(remaining.map((i) => i.cardKey).toSet(), {_key(2)});
    });
  });

  group('OfficialAnkiHomeDue card-id formal due', () {
    setUp(OfficialFormalDueRepository.instance.resetForTest);
    tearDown(() {
      OfficialFormalDueRepository.instance.resetForTest();
    });

    test('prefers key intersection when scheduler due ids are known', () {
      final repo = OfficialFormalDueRepository.instance;
      repo.commit(
        OfficialFormalDueUpdate(
          bySource: {
            'src-a': buildFormalDuePerSource(
              importId: 'src-a',
              schedulerDueCardIds: const {1, 2, 3, 4},
              schedulerDueSynced: true,
              activePlacementCardIds: const {1, 2, 3},
              suspendedCardIds: const {2},
              buriedCardIds: const {},
              retiredCardIds: const {},
            ),
          },
          rawDueBySource: const {},
          turnaDue: 0,
          unintroducedNew: 0,
        ),
        basedOnGeneration: repo.generation,
      );

      // P1: a post-lock schedulerDue never contains suspended cards, so the
      // suspended set here is informational and the formula no longer
      // subtracts it — placement still scopes, though.
      expect(
        repo.formalDueCardKeysForImport('src-a'),
        {_key(1), _key(2), _key(3)},
      );
      expect(repo.formalOfficialDueForImport('src-a'), 3);
    });
  });
}
