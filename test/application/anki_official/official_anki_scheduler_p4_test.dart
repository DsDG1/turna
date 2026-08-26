import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_snapshot_builder.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_update.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/engine/official_anki_scheduler_audit.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/render/official_anki_present_ack.dart';
import 'package:turna/views/anki_official/official_anki_review_page.dart';

import 'official_anki_formal_review_ack_test.dart' show officialFormalReviewPresenter;

void main() {
  test('contract 1.6 publishes scheduler operations 11-16 and 27-34', () {
    expect(kOfficialAnkiContractMinor, 6);
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
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.deleteNotes), 31);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.deleteCards), 32);
    expect(
      OfficialAnkiOperation.idFor(OfficialAnkiOperation.statsForCardsBatch),
      33,
    );
    expect(
      OfficialAnkiOperation.idFor(OfficialAnkiOperation.scheduleCardsAsNew),
      34,
    );
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
        'DELETE_NOTES',
        'DELETE_CARDS',
        'STATS_FOR_CARDS_BATCH',
        'SCHEDULE_CARDS_AS_NEW',
      ]),
    );
    final golden = jsonDecode(
      File('native/turna_anki_core/contract/fixtures/response_engine_info.json')
          .readAsStringSync(),
    ) as Map;
    final caps = (golden['payload'] as Map)['capabilities'] as List;
    expect(caps, contains('GET_REVIEW_QUEUE'));
    expect(caps, contains('REDO'));
    expect(caps, contains('DELETE_NOTES'));
    expect(caps, contains('SCHEDULE_CARDS_AS_NEW'));
    expect(
      File('native/turna_anki_core/contract/VERSION')
          .readAsStringSync()
          .trim(),
      '1.6',
    );
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
    await session.buryOrSuspend(OfficialBuryOrSuspendAction.suspend);
    expect(OfficialAnkiSchedulerAudit.turnaSrsWritesFromOfficialPath, 0);
    expect(OfficialAnkiSchedulerAudit.legacyCallsFromOfficialPath, 0);
    expect(OfficialAnkiSchedulerAudit.courseProjectionWritesDuringReview, 0);
    final counts = await fake.countsForDeckToday(1);
    expect(counts.deckId, 1);
    final congrats = await fake.congratsInfo();
    expect(congrats.secsUntilNextLearn, greaterThan(0));
  });

  test('home due stores stay dual-source and scheduler route exists', () {
    final repo = OfficialFormalDueRepository.instance;
    repo.resetForTest();
    repo.commit(
      OfficialFormalDueUpdate(
        bySource: {
          'src-x': buildFormalDuePerSource(
            importId: 'src-x',
            schedulerDueCardIds: const {1, 2, 3, 4, 5, 6, 7},
            schedulerDueSynced: true,
            activePlacementCardIds: const {1, 2, 3, 4, 5, 6, 7},
            suspendedCardIds: const {},
            buriedCardIds: const {},
            retiredCardIds: const {},
          ),
        },
        rawDueBySource: const {'src-x': 7},
        turnaDue: 0,
        unintroducedNew: 0,
      ),
      basedOnGeneration: repo.generation,
    );
    // Dual-source stores: raw official totals live per-import;
    // officialDue itself is derived (introduced-only).
    expect(repo.snapshot.rawDueByImport['src-x'], 7);
    expect(repo.snapshot.introducedOfficialDue, 0);
    expect(OfficialAnkiReviewPage.routeName, '/official-anki/review');
    expect(
      OfficialAnkiFeatureFlags.fromEnvironment().scheduler,
      isTrue,
    );
  });

  test('preview path does not increment official scheduler answers', () {
    OfficialAnkiSchedulerAudit.reset();
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 0);
    expect(OfficialAnkiSchedulerAudit.officialSchedulerWritesFromPreview, 0);
    expect(
      OfficialAnkiSchedulerAudit.officialSchedulerWritesFromDerivedExercise,
      0,
    );
    // The Phase-0 spike was removed from the production tree (duplicate FFI
    // bindings had drifted from the transport); keep it out.
    expect(
      Directory('lib/application/anki_official/spike').existsSync(),
      isFalse,
    );
    final reviewSource = File(
      'lib/application/anki_official/engine/official_anki_review_session.dart',
    ).readAsStringSync();
    expect(reviewSource.contains('official_anki_spike_models'), isFalse);
    final preview = File(
      'lib/views/anki_official/official_anki_canonical_link_view.dart',
    ).readAsStringSync();
    expect(preview.contains('official-review-again'), isFalse);
    expect(preview.contains('official-review-good'), isFalse);
    expect(preview.contains('answerCard'), isFalse);
    expect(preview.contains('OfficialAnkiReviewPage'), isFalse);
    final reviewer = File(
      'lib/views/anki_official/official_anki_reviewer_page.dart',
    ).readAsStringSync();
    expect(reviewer.contains('official-review-good'), isFalse);
    expect(reviewer.contains('Does not write grades'), isTrue);
  });

  test('session measures answer-visible elapsed and does not replay unknown',
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
    expect(session.phase, OfficialReviewPhase.showingQuestion);
    expect(session.answerVisibleElapsed.isRunning, isFalse);
    session.showAnswer();
    expect(session.answerVisibleElapsed.isRunning, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    await session.answer('good');
    expect(fake.lastMillisecondsTaken, greaterThan(0));
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 1);

    await session.openDeck(1);
    session.showAnswer();
    fake.failNextAnswerUnknown = true;
    final answersBefore = OfficialAnkiSchedulerAudit.officialSchedulerAnswers;
    await session.answer('again');
    expect(session.lastError?.code, OfficialAnkiErrorCode.answerCommitUnknown);
    expect(session.phase, isNot(OfficialReviewPhase.committingAnswer));
    expect(
      OfficialAnkiSchedulerAudit.officialSchedulerAnswers,
      answersBefore,
    );
  });

  test('double answer while in flight is a single official write', () async {
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
    session.inFlight = true;
    await session.answer('good');
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 0);
    session.inFlight = false;
    final first = session.answer('good');
    final second = session.answer('easy');
    await Future.wait<void>([first, second]);
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 1);
  });

  testWidgets('formal review ratings stay disabled until answer present ACK',
      (tester) async {
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
    final paths = OfficialAnkiPaths(
      profileId: 'profile-review01',
      profileRoot: Directory.systemTemp.createTempSync('turna-review-ui-'),
    );
    addTearDown(() {
      if (paths.profileRoot.existsSync()) {
        paths.profileRoot.deleteSync(recursive: true);
      }
    });
    final presenter = await officialFormalReviewPresenter(fake);
    addTearDown(presenter.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: OfficialAnkiReviewPage(
          engine: fake,
          paths: paths,
          flags: flags,
          session: session,
          presenter: presenter,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final toggle = find.byKey(const Key('official-review-toggle-surface'));
    if (toggle.evaluate().isNotEmpty) {
      final button = tester.widget<IconButton>(toggle);
      if (button.onPressed != null) {
        await tester.tap(toggle);
        await tester.pump();
      }
    }
    expect(find.byKey(const Key('official-review-show-answer')), findsOneWidget);
    expect(find.byKey(const Key('official-review-good')), findsNothing);
    presenter.acceptPresent(
      OfficialPresentAck(
        cardId: presenter.presentedCardId,
        generation: presenter.presentGeneration,
        side: 'question',
        ok: true,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('official-review-show-answer')));
    await tester.pump();
    expect(find.byKey(const Key('official-review-good')), findsNothing);
    presenter.acceptPresent(
      OfficialPresentAck(
        cardId: presenter.presentedCardId,
        generation: presenter.presentGeneration,
        side: 'answer',
        ok: true,
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('official-review-again')), findsOneWidget);
    expect(find.byKey(const Key('official-review-good')), findsOneWidget);
    expect(find.byKey(const Key('official-review-hard')), findsNothing);
    expect(find.byKey(const Key('official-review-easy')), findsNothing);
  });

  test('allowedCardIds skips leftover deck mates and does not answer them', () async {
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
    final session = OfficialReviewSession(
      engine: fake,
      flags: flags,
      allowedCardIds: {2},
    );
    await session.openDeck(1);
    expect(session.phase, OfficialReviewPhase.showingQuestion);
    expect(session.current?.cardId, 2);
    session.showAnswer();
    await session.answer('good');
    expect(fake.answeredIds, {2});
    expect(fake.answeredIds.contains(1), isFalse);
    expect(session.phase, OfficialReviewPhase.completed);
    expect(session.current, isNull);
  });

  test('allowedCardIds completes when only leftover cards remain', () async {
    OfficialAnkiSchedulerAudit.reset();
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
    fake.answeredIds.add(2);
    const flags = OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
      renderer: true,
      scheduler: true,
    );
    final session = OfficialReviewSession(
      engine: fake,
      flags: flags,
      allowedCardIds: {2},
    );
    await session.openDeck(1);
    expect(session.phase, OfficialReviewPhase.completed);
    expect(session.current, isNull);
    expect(fake.answeredIds.contains(1), isFalse);
  });

  test('queueEmpty clears current so completed is not an invalid state', () async {
    OfficialAnkiSchedulerAudit.reset();
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
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
    expect(session.current, isNotNull);
    fake.buried.add(session.current!.cardId);
    await session.refreshQueue();
    expect(session.phase, OfficialReviewPhase.completed);
    expect(session.current, isNull);
    expect(session.isCompleted, isTrue);
    expect(session.congrats, isNotNull);
  });

  test('openDueDeck skips empty Default and opens the imported deck', () async {
    OfficialAnkiSchedulerAudit.reset();
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
    fake.cards.remove(1);
    fake.cards[99] = const OfficialAnkiCardDescriptor(
      cardId: 99,
      noteId: 50,
      deckId: 2,
      templateOrd: 0,
      noteGuid: 'guid-imported',
    );
    fake.deckTree = const [
      OfficialAnkiDeckNode(deckId: 1, name: 'Default', level: 0),
      OfficialAnkiDeckNode(
        deckId: 2,
        name: 'Imported',
        level: 0,
        newCount: 1,
      ),
    ];
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
    await session.openDueDeck();
    expect(session.phase, OfficialReviewPhase.showingQuestion);
    expect(session.current?.cardId, 99);
    expect(session.current?.deckId, 2);
    expect(fake.currentDeckId, 2);
  });

  test('deck tree JSON keeps snake-case due counts', () {
    final node = OfficialAnkiDeckNode.fromJson({
      'deck_id': 7,
      'name': 'Source',
      'level': 1,
      'new_count': 3,
      'learn_count': 1,
      'review_count': 8,
    });
    expect(node.deckId, 7);
    expect(node.dueCount, 12);
    final ordered = OfficialReviewSession.orderDecksForReview([
      const OfficialAnkiDeckNode(deckId: 1, name: 'Default', newCount: 1),
      const OfficialAnkiDeckNode(deckId: 0, name: ''),
      const OfficialAnkiDeckNode(deckId: 4, name: 'Source', newCount: 1),
    ]);
    expect(ordered.map((d) => d.deckId), [4, 1]);
  });
}
