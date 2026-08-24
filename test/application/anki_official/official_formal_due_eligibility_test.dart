import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/card_introduction_store.dart';
import 'package:turna/application/anki/official_study_batch_assembler.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
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
    test('exact intersection minus suspended/buried/retired', () {
      final due = computeFormalDueCardKeys(
        officialSchedulerDueCardKeys: {_key(1), _key(2), _key(3), _key(4)},
        activePlacementCardKeys: {_key(1), _key(2), _key(3)},
        introducedCardKeys: {_key(1), _key(2), _key(4)},
        suspendedCardKeys: {_key(2)},
        buriedCardKeys: const {},
        retiredCardKeys: {_key(4)},
      );
      expect(due, {_key(1)});
    });

    test('does not use count approximation', () {
      final due = computeFormalDueCardKeysForSource(
        sourceId: 'src-a',
        officialSchedulerDueCardIds: {10, 11, 12, 13, 14},
        activePlacementCardIds: {10, 11, 12, 13, 14},
        introducedCardIds: {11, 99},
      );
      expect(due.map((k) => k.cardId).toSet(), {11});
      expect(due.length, 1);
    });

    test('unintroduced new cards stay out of formal queue', () {
      final due = computeFormalDueCardKeys(
        officialSchedulerDueCardKeys: {_key(1), _key(2)},
        activePlacementCardKeys: {_key(1), _key(2)},
        introducedCardKeys: {_key(1)},
      );
      expect(due, {_key(1)});
    });
  });

  group('OfficialStudyBatchAssembler', () {
    test('assembles only formal-due cards with presentations', () {
      final presentations = <CanonicalCardKey, CardPresentation>{
        _key(1): _flip(_key(1), 'a', 'b'),
        _key(2): _flip(_key(2), 'c', 'd'),
      };
      final items = const OfficialStudyBatchAssembler().assembleFromEligibility(
        sourceId: 'src-a',
        courseId: 'course-src-a',
        queueCards: [_queueCard(1), _queueCard(2), _queueCard(3)],
        presentations: presentations,
        activePlacementCardKeys: {_key(1), _key(2), _key(3)},
        introducedCardKeys: {_key(1), _key(2)},
        buriedCardKeys: {_key(2)},
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
    setUp(OfficialAnkiHomeDue.reset);
    tearDown(() {
      OfficialAnkiHomeDue.reset();
      CardIntroductionStore.debugOverride = null;
    });

    test('prefers key intersection when scheduler due ids are known', () async {
      final store = CardIntroductionStore();
      CardIntroductionStore.debugOverride = store;
      OfficialAnkiHomeDue.officialSchedulerDueCardIdsByImport = {
        'src-a': {1, 2, 3, 4},
      };
      OfficialAnkiHomeDue.activePlacementCardIdsByImport = {
        'src-a': {1, 2, 3},
      };
      OfficialAnkiHomeDue.suspendedCardIdsByImport = {
        'src-a': {2},
      };
      await store.markFromLesson(
        wordId: 'official-anki-src-a-c1',
        lessonId: 'official-anki-src-a-l0123456789ab-p0',
      );
      await store.markFromLesson(
        wordId: 'official-anki-src-a-c3',
        lessonId: 'official-anki-src-a-l0123456789ab-p0',
      );

      expect(
        OfficialAnkiHomeDue.formalDueCardKeysForImport('src-a'),
        {_key(1), _key(3)},
      );
      expect(OfficialAnkiHomeDue.formalOfficialDueForImport('src-a'), 2);
    });
  });
}
