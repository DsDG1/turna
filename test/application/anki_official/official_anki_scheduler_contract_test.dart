import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_scheduler_audit.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';

void main() {
  final validCard = <String, Object?>{
    'cardId': 11,
    'noteId': 7,
    'deckId': 1,
    'templateOrdinal': 0,
    'queueKind': 'review',
    'answerToken': 'tok-session-1-11',
    'labels': {
      'again': '1m',
      'hard': '6d',
      'good': '15d',
      'easy': '1mo',
    },
  };

  final validQueue = <String, Object?>{
    'sessionId': 'session-1',
    'queueEpoch': 3,
    'newCount': 1,
    'learningCount': 0,
    'reviewCount': 2,
    'cards': [validCard],
    'futureField': 'ignore',
  };

  Matcher isContractError() => isA<OfficialAnkiException>().having(
        (e) => e.code,
        'code',
        OfficialAnkiErrorCode.invalidArgument,
      );

  test('queue decode keeps unknown fields and requires identities', () {
    final queue = OfficialReviewQueue.fromJson(validQueue);
    expect(queue.sessionId, 'session-1');
    expect(queue.queueEpoch, 3);
    expect(queue.cards.single.cardId, 11);
    expect(queue.cards.single.answerToken, 'tok-session-1-11');
  });

  test('malformed scheduler responses fail closed', () {
    final cases = <Map<String, Object?>>[
      {...validQueue, 'sessionId': ''},
      {...validQueue, 'queueEpoch': 0},
      {...validQueue}..remove('cards'),
      {
        ...validQueue,
        'cards': [
          {...validCard, 'cardId': 0},
        ],
      },
      {
        ...validQueue,
        'cards': [
          {...validCard, 'answerToken': ''},
        ],
      },
      {
        ...validQueue,
        'cards': [
          {...validCard}..remove('labels'),
        ],
      },
      {
        ...validQueue,
        'cards': [
          {
            ...validCard,
            'labels': {'again': '1m', 'hard': '6d', 'good': '15d', 'easy': ''},
          },
        ],
      },
    ];
    for (final json in cases) {
      expect(
        () => OfficialReviewQueue.fromJson(json),
        throwsA(isContractError()),
        reason: '$json',
      );
    }
  });

  test('answer and mutation results read required wire fields', () {
    final answered = OfficialAnswerResult.fromJson({
      'cardId': 11,
      'queue': 'review',
      'revlogCount': 4,
      'millisecondsTaken': 1200,
      'rating': 'good',
      'queueEpoch': 4,
      'committed': true,
      'extra': true,
    });
    expect(answered.committed, isTrue);
    expect(answered.rating, 'good');

    expect(
      () => OfficialAnswerResult.fromJson({
        'cardId': 11,
        'queue': 'review',
        'revlogCount': 4,
        'millisecondsTaken': 1200,
        'rating': 'good',
        'queueEpoch': 4,
      }),
      throwsA(isContractError()),
    );
    expect(
      () => OfficialAnswerResult.fromJson({
        'cardId': 0,
        'queue': 'review',
        'revlogCount': 4,
        'millisecondsTaken': 1200,
        'rating': 'good',
        'queueEpoch': 4,
        'committed': true,
      }),
      throwsA(isContractError()),
    );

    final mutation = OfficialMutationResult.fromJson({
      'ok': false,
      'undone': true,
      'queueEpoch': 5,
    });
    expect(mutation.ok, isFalse);
    expect(
      () => OfficialMutationResult.fromJson({
        'undone': true,
        'queueEpoch': 5,
      }),
      throwsA(isContractError()),
    );
    expect(
      () => OfficialMutationResult.fromJson({
        'ok': true,
        'queueEpoch': 0,
      }),
      throwsA(isContractError()),
    );
  });

  test('worker_unknown_bury_action_fails_closed', () async {
    OfficialAnkiSchedulerAudit.reset();
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
    expect(
      () => dispatchOfficialAnkiScheduler(fake, {
        'op': 'buryOrSuspendCards',
        'action': 'not-a-real-action',
        'cardIds': [1],
      }),
      throwsA(
        isA<OfficialAnkiException>()
            .having(
              (e) => e.code,
              'code',
              OfficialAnkiErrorCode.invalidArgument,
            )
            .having(
              (e) => e.messageKey,
              'messageKey',
              'official_anki.invalid_bury_action',
            ),
      ),
    );
    expect(fake.buried, isEmpty);
    expect(fake.suspended, isEmpty);
    expect(OfficialAnkiSchedulerAudit.officialSchedulerBurySuspend, 0);

    await dispatchOfficialAnkiScheduler(fake, {
      'op': 'buryOrSuspendCards',
      'action': 'suspend',
      'cardIds': [1],
    });
    expect(fake.suspended, {1});
  });

  test('worker reject empty or non-positive bury card ids', () async {
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
    expect(
      () => dispatchOfficialAnkiScheduler(fake, {
        'op': 'buryOrSuspendCards',
        'action': 'buryUser',
        'cardIds': <int>[],
      }),
      throwsA(isContractError()),
    );
    expect(
      () => dispatchOfficialAnkiScheduler(fake, {
        'op': 'buryOrSuspendCards',
        'action': 'buryUser',
        'cardIds': [0, 1],
      }),
      throwsA(isContractError()),
    );
    expect(fake.buried, isEmpty);
  });
}
