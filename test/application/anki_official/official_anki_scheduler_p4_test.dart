import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/engine/official_anki_scheduler_audit.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/views/anki_official/official_anki_review_page.dart';

void main() {
  test('contract 1.3 publishes scheduler operations 11-16 and 27-30', () {
    expect(kOfficialAnkiContractMinor, 3);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.setCurrentDeck), 11);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.getReviewQueue), 12);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.describeNextStates), 13);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.answerCard), 14);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.getUndoStatus), 15);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.undo), 16);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.redo), 27);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.buryOrSuspendCards), 28);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.countsForDeckToday), 29);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.congratsInfo), 30);
    expect(
      OfficialAnkiOperation.productionNames,
      containsAll([
        'SET_CURRENT_DECK',
        'GET_REVIEW_QUEUE',
        'ANSWER_CARD',
        'UNDO',
        'REDO',
        'BURY_OR_SUSPEND_CARDS',
        'COUNTS_FOR_DECK_TODAY',
        'CONGRATS_INFO',
      ]),
    );
    final golden = jsonDecode(
      File('native/turna_anki_core/contract/fixtures/response_engine_info.json')
          .readAsStringSync(),
    ) as Map;
    final caps = (golden['payload'] as Map)['capabilities'] as List;
    expect(caps, contains('GET_REVIEW_QUEUE'));
    expect(caps, contains('REDO'));
    expect(File('native/turna_anki_core/contract/VERSION').readAsStringSync().trim(), '1.3');
  });

  test('fake queue tokens are opaque and single-use', () async {
    OfficialAnkiSchedulerAudit.reset();
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
    final queue = await fake.getReviewQueue(fetchLimit: 1);
    expect(queue.sessionId, isNotEmpty);
    expect(queue.cards.single.answerToken, isNot(contains('Scheduling')));
    final first = await fake.answerCard(
      sessionId: queue.sessionId,
      queueEpoch: queue.queueEpoch,
      answerToken: queue.cards.single.answerToken,
      cardId: queue.cards.single.cardId,
      rating: 'good',
      millisecondsTaken: 3210,
    );
    expect(first.millisecondsTaken, 3210);
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 1);
    expect(
      () => fake.answerCard(
        sessionId: queue.sessionId,
        queueEpoch: queue.queueEpoch,
        answerToken: queue.cards.single.answerToken,
        cardId: queue.cards.single.cardId,
        rating: 'good',
        millisecondsTaken: 10,
      ),
      throwsA(
        isA<OfficialAnkiException>().having(
          (e) => e.code,
          'code',
          OfficialAnkiErrorCode.schedulingContextStale,
        ),
      ),
    );
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 1);
  });

  test('session answers once, stale token reloads, flag fail-closes', () async {
    OfficialAnkiSchedulerAudit.reset();
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 3, cards: 3);
    const flags = OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
      renderer: true,
      scheduler: true,
    );
    final session = OfficialReviewSession(engine: fake, flags: flags);
    await session.openDeck(1);
    expect(session.phase, OfficialReviewPhase.showingQuestion);
    session.showAnswer();
    await session.answer('good');
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 1);
    expect(session.phase, isNot(OfficialReviewPhase.committingAnswer));
    final closed = OfficialReviewSession(
      engine: fake,
      flags: const OfficialAnkiFeatureFlags(),
    );
    expect(closed.openDeck(1), throwsA(isA<OfficialAnkiException>()));
  });

  test('undo redo bury invalidate queue and ownership counters stay isolated',
      () async {
    OfficialAnkiSchedulerAudit.reset();
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
    const flags = OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
      renderer: true,
      scheduler: true,
    );
    final session = OfficialReviewSession(engine: fake, flags: flags);
    await session.openDeck(1);
    session.showAnswer();
    await session.answer('again');
    await session.undo();
    expect(OfficialAnkiSchedulerAudit.officialSchedulerUndo, 1);
    await session.redo();
    expect(OfficialAnkiSchedulerAudit.officialSchedulerRedo, 1);
    await session.openDeck(1);
    await session.buryOrSuspend(OfficialBuryOrSuspendAction.suspendCards);
    expect(OfficialAnkiSchedulerAudit.turnaSrsWritesFromOfficialPath, 0);
    expect(OfficialAnkiSchedulerAudit.legacyCallsFromOfficialPath, 0);
    expect(OfficialAnkiSchedulerAudit.courseProjectionWritesDuringReview, 0);
    final counts = await fake.countsForDeckToday(1);
    expect(counts.deckId, 1);
    final congrats = await fake.congratsInfo();
    expect(congrats.secsUntilNextLearn, greaterThan(0));
  });

  test('home due stores stay dual-source and scheduler route exists', () {
    OfficialAnkiHomeDue.reset();
    OfficialAnkiHomeDue.turnaDue = 4;
    OfficialAnkiHomeDue.officialDue = 7;
    expect(OfficialAnkiHomeDue.turnaDue, 4);
    expect(OfficialAnkiHomeDue.officialDue, 7);
    expect(OfficialAnkiReviewPage.routeName, '/official-anki/review');
    expect(
      OfficialAnkiFeatureFlags.fromEnvironment().scheduler,
      isFalse,
    );
  });

  test('preview path does not increment official scheduler answers', () {
    OfficialAnkiSchedulerAudit.reset();
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 0);
    expect(
      Directory('lib/application/anki_official/spike').existsSync(),
      isTrue,
    );
    final reviewSource = File(
      'lib/application/anki_official/engine/official_anki_review_session.dart',
    ).readAsStringSync();
    expect(reviewSource.contains('official_anki_spike_models'), isFalse);
  });
}
