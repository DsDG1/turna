import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/card_presentation_policy.dart';
import 'package:turna/application/anki/study_session_controller.dart';
import 'package:turna/application/anki/unification/in_memory_anki_unification_store.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_practice/card_classifier_models.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/course_card_placement.dart';
import 'package:turna/domain/anki/objective_outcome.dart';
import 'package:turna/domain/anki/presentation_receipt.dart';
import 'package:turna/domain/anki/review_queue_snapshot.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/review/recall_outcome.dart';

void main() {
  const profile = 'profile-a';
  const courseId = 'course-1';
  const sourceId = 'src-1';

  CanonicalCardKey key(int cardId) => CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: profile,
        sourceId: sourceId,
        cardId: cardId,
      );

  FlipCardPresentation flipFor(CanonicalCardKey cardKey) => FlipCardPresentation(
        cardKey: cardKey,
        frontText: 'front-${cardKey.cardId}',
        backText: 'back-${cardKey.cardId}',
        sourceFingerprint: 'fp',
      );

  CourseCardPlacement placementFor(CanonicalCardKey cardKey, {int order = 0}) {
    return CourseCardPlacement(
      placementId: 'p-${cardKey.cardId}',
      courseId: courseId,
      cardKey: cardKey,
      sectionId: 's1',
      unitId: 'u1',
      lessonId: 'l1',
      order: order,
    );
  }

  group('CanonicalCardKey', () {
    test('equality and hash treat backend/source/card as identity', () {
      final a = key(10);
      final b = key(10);
      final c = key(11);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(
        CanonicalCardKey(
          backend: AnkiBackendKind.legacyTurna,
          profileId: profile,
          sourceId: sourceId,
          cardId: 10,
        ),
        isNot(a),
      );
    });

    test('adapter parses stored ids once; key itself has no prefix API', () {
      final source =
          File('lib/domain/anki/canonical_card_key.dart').readAsStringSync();
      expect(source.contains("startsWith('anki-')"), isFalse);
      expect(source.contains("startsWith('official-anki-')"), isFalse);

      final official = CanonicalCardKeyAdapter.tryParseStoredWordId(
        profileId: profile,
        rawId: 'official-anki-src-1-c42',
      );
      expect(official, key(42));
      final legacy = CanonicalCardKeyAdapter.tryParseStoredWordId(
        profileId: profile,
        rawId: 'anki-import1-c7',
      );
      expect(legacy?.backend, AnkiBackendKind.legacyTurna);
      expect(legacy?.cardId, 7);
      expect(
        CanonicalCardKeyAdapter.tryParseStoredWordId(
          profileId: profile,
          rawId: 'vocab-plain',
        ),
        isNull,
      );
    });

    test('note templates produce distinct card ids', () {
      expect(key(1), isNot(key(2)));
    });
  });

  group('Presentation policy', () {
    test('ordinary vocab with sibling answers is Flip, not MCQ', () {
      const values = OfficialAnkiRoleValues(
        target: 'cat',
        native: '猫',
        pronunciation: '',
        example: '',
        audio: null,
        image: null,
        options: ['dog', 'bird', 'fish'],
        truncatedRequired: false,
        hasExplicitOptions: false,
        classification: AnkiPracticeClassification(
          shape: AnkiPracticeShape.vocab,
          confidence: 0.9,
          term: 'cat',
          meaning: '猫',
        ),
      );
      final kind = const CardPresentationPolicy().selectOfficialKind(
        values: values,
        mapping: const OfficialAnkiMappingSuggestion(
          candidates: [],
          status: OfficialAnkiMappingStatus.autoCandidate,
        ),
        typeAnswerEnabled: true,
      );
      expect(kind, OfficialAnkiProjectionKind.flip);
      expect(
        OfficialAnkiProjectionPayloads().kindsFor(
          values: values,
          mapping: const OfficialAnkiMappingSuggestion(
          candidates: [],
          status: OfficialAnkiMappingStatus.autoCandidate,
        ),
          typeAnswerEnabled: true,
        ),
        [OfficialAnkiProjectionKind.flip],
      );
    });

    test('explicit option pool keeps a single MCQ', () {
      const values = OfficialAnkiRoleValues(
        target: 'Paris',
        native: '首都',
        pronunciation: '',
        example: '',
        audio: null,
        image: null,
        options: ['Paris', 'London', 'Berlin', 'Madrid'],
        truncatedRequired: false,
        hasExplicitOptions: true,
        classification: AnkiPracticeClassification(
          shape: AnkiPracticeShape.vocab,
          confidence: 0.9,
          term: 'Paris',
          meaning: '首都',
          options: ['Paris', 'London', 'Berlin', 'Madrid'],
        ),
      );
      expect(
        OfficialAnkiProjectionPayloads().kindsFor(
          values: values,
          mapping: const OfficialAnkiMappingSuggestion(
          candidates: [],
          status: OfficialAnkiMappingStatus.autoCandidate,
        ),
          typeAnswerEnabled: true,
        ),
        [OfficialAnkiProjectionKind.multipleChoice],
      );
    });

    test('kindsFor always returns exactly one kind', () {
      const values = OfficialAnkiRoleValues(
        target: 'hello',
        native: '你好',
        pronunciation: '',
        example: '',
        audio: 'a.mp3',
        image: 'b.png',
        options: ['x', 'y', 'z'],
        truncatedRequired: false,
        hasExplicitOptions: true,
        classification: AnkiPracticeClassification(
          shape: AnkiPracticeShape.vocab,
          confidence: 0.95,
          term: 'hello',
          meaning: '你好',
          audioFilename: 'a.mp3',
          options: ['x', 'y', 'z'],
        ),
      );
      final kinds = OfficialAnkiProjectionPayloads().kindsFor(
        values: values,
        mapping: const OfficialAnkiMappingSuggestion(
          candidates: [],
          status: OfficialAnkiMappingStatus.autoCandidate,
        ),
        typeAnswerEnabled: true,
      );
      expect(kinds, hasLength(1));
    });
  });

  group('Objective outcome', () {
    test('maps correct/incorrect onto remembered/forgotten', () {
      expect(
        objectiveRecallOutcome(correct: true),
        RecallOutcome.remembered,
      );
      expect(
        objectiveRecallOutcome(correct: false),
        RecallOutcome.forgotten,
      );
    });
  });

  group('Introduction and review eligibility', () {
    test('unintroduced cards never enter the formal review queue', () async {
      final due = {key(1), key(2), key(3)};
      final store = InMemoryAnkiUnificationStore(
        dueLookup: (_) async => due,
      );
      for (var i = 1; i <= 3; i++) {
        store.seedPlacement(placementFor(key(i), order: i));
        store.seedPresentation(flipFor(key(i)), courseId: courseId);
      }

      final before = await store.build(courseId: courseId);
      expect(before.introducedDue, 0);
      expect(before.unintroducedNew, 3);
      expect(before.items, isEmpty);
      expect(before.freshness, ReviewQueueFreshness.ready);

      await store.markIntroduced(
        courseId,
        key(1),
        by: CardIntroducedBy.course,
        lessonId: 'l1',
      );
      await store.markIntroduced(
        courseId,
        key(2),
        by: CardIntroducedBy.importedHistory,
        lessonId: 'l1',
      );

      final after = await store.build(courseId: courseId);
      expect(after.introducedDue, 2);
      expect(after.unintroducedNew, 1);
      expect(after.items.map((item) => item.cardKey.cardId), [1, 2]);
    });

    test('practice and retired cards stay out of the due intersection', () async {
      final store = InMemoryAnkiUnificationStore(
        dueLookup: (_) async => {key(1), key(2)},
      );
      store.seedPlacement(placementFor(key(1)));
      store.seedPlacement(placementFor(key(2), order: 1));
      store.seedPresentation(flipFor(key(1)), courseId: courseId);
      store.seedPresentation(flipFor(key(2)), courseId: courseId);
      await store.markIntroduced(
        courseId,
        key(1),
        by: CardIntroducedBy.course,
        lessonId: 'l1',
      );
      await store.markIntroduced(
        courseId,
        key(2),
        by: CardIntroducedBy.course,
        lessonId: 'l1',
      );
      await store.retire(courseId, key(2));

      final snapshot = await store.build(courseId: courseId);
      expect(snapshot.items.map((item) => item.cardKey.cardId), [1]);
    });

    test('duplicate active placement is rejected', () {
      final store = InMemoryAnkiUnificationStore();
      store.seedPlacement(placementFor(key(1)));
      expect(
        () => store.seedPlacement(
          CourseCardPlacement(
            placementId: 'other',
            courseId: courseId,
            cardKey: key(1),
            sectionId: 's1',
            unitId: 'u1',
            lessonId: 'l2',
            order: 1,
          ),
        ),
        throwsStateError,
      );
    });
  });

  group('StudySessionController', () {
    test('flip commit requires answer receipt and writes one ledger event',
        () async {
      final ledger = _FakeStudyLedger();
      final store = InMemoryAnkiUnificationStore();
      final item = StudyItem(
        sessionItemId: 's1',
        courseId: courseId,
        placementId: 'p-1',
        cardKey: key(1),
        presentation: flipFor(key(1)),
        mode: StudyMode.learn,
        ledgerOwner: StudyLedgerOwner.turnaFsrs,
        capabilities: StudyCapabilities.forMode(StudyMode.learn),
      );
      final controller = StudySessionController(
        items: [item],
        ledgerResolver: StudyLedgerResolver(turna: ledger),
        introductionRepository: store,
      );
      await controller.start();
      expect(controller.canReveal, isFalse);
      controller.acceptPresentation(_receipt(item, controller, PresentationSide.question));
      expect(controller.canReveal, isTrue);
      expect(controller.canSubmitRecall, isFalse);

      await controller.revealAnswer();
      expect(controller.canSubmitRecall, isFalse);
      controller.acceptPresentation(_receipt(item, controller, PresentationSide.answer));
      expect(controller.canSubmitRecall, isTrue);

      await controller.submitRecall(RecallOutcome.remembered);
      expect(ledger.commits, 1);
      expect(controller.phase, StudyCardPhase.readyForNext);
      expect(
        (await store.stateFor(courseId, key(1))).isIntroduced,
        isTrue,
      );
    });

    test('stale generation ACK is ignored', () async {
      final ledger = _FakeStudyLedger();
      final item = StudyItem(
        sessionItemId: 's1',
        courseId: courseId,
        placementId: 'p-1',
        cardKey: key(1),
        presentation: flipFor(key(1)),
        mode: StudyMode.review,
        ledgerOwner: StudyLedgerOwner.turnaFsrs,
        capabilities: StudyCapabilities.forMode(StudyMode.review),
      );
      final controller = StudySessionController(
        items: [item],
        ledgerResolver: StudyLedgerResolver(turna: ledger),
      );
      await controller.start();
      controller.acceptPresentation(
        PresentationReceipt(
          cardKey: key(1),
          generation: controller.generation - 1,
          side: PresentationSide.question,
          renderer: PresentationRendererKind.flutterFlip,
          presentedAt: DateTime.now(),
        ),
      );
      expect(controller.canReveal, isFalse);
    });

    test('ledger failure does not advance and retry reuses idempotency key',
        () async {
      final ledger = _FakeStudyLedger()..failOnce = true;
      final item = StudyItem(
        sessionItemId: 's1',
        courseId: courseId,
        placementId: 'p-1',
        cardKey: key(1),
        presentation: flipFor(key(1)),
        mode: StudyMode.review,
        ledgerOwner: StudyLedgerOwner.turnaFsrs,
        capabilities: StudyCapabilities.forMode(StudyMode.review),
      );
      final controller = StudySessionController(
        items: [item],
        ledgerResolver: StudyLedgerResolver(turna: ledger),
      );
      await controller.start();
      controller.acceptPresentation(_receipt(item, controller, PresentationSide.question));
      await controller.revealAnswer();
      controller.acceptPresentation(_receipt(item, controller, PresentationSide.answer));
      await controller.submitRecall(RecallOutcome.forgotten);
      expect(controller.phase, StudyCardPhase.recoverableError);
      expect(ledger.commits, 0);

      await controller.retryCurrent();
      controller.acceptPresentation(_receipt(item, controller, PresentationSide.question));
      await controller.revealAnswer();
      controller.acceptPresentation(_receipt(item, controller, PresentationSide.answer));
      await controller.submitRecall(RecallOutcome.forgotten);
      expect(ledger.commits, 1);
      final firstKey = ledger.idempotencyKeys.single;
      await controller.submitRecall(RecallOutcome.forgotten);
      expect(ledger.commits, 1);
      expect(ledger.idempotencyKeys, [firstKey]);
    });

    test('practice mode does not write the ledger', () async {
      final ledger = _FakeStudyLedger();
      final item = StudyItem(
        sessionItemId: 's1',
        courseId: courseId,
        placementId: 'p-1',
        cardKey: key(1),
        presentation: flipFor(key(1)),
        mode: StudyMode.practice,
        ledgerOwner: StudyLedgerOwner.none,
        capabilities: StudyCapabilities.forMode(StudyMode.practice),
      );
      final controller = StudySessionController(
        items: [item],
        ledgerResolver: StudyLedgerResolver(turna: ledger),
      );
      await controller.start();
      controller.acceptPresentation(_receipt(item, controller, PresentationSide.question));
      await controller.revealAnswer();
      controller.acceptPresentation(_receipt(item, controller, PresentationSide.answer));
      await controller.submitRecall(RecallOutcome.remembered);
      expect(ledger.commits, 0);
      expect(controller.phase, StudyCardPhase.readyForNext);
    });

    test('objective answer maps to a single forgotten commit', () async {
      final ledger = _FakeStudyLedger();
      final item = StudyItem(
        sessionItemId: 's1',
        courseId: courseId,
        placementId: 'p-1',
        cardKey: key(1),
        presentation: StructuredCardPresentation(
          cardKey: key(1),
          kind: CardPresentationKind.multipleChoice,
          interaction: const Interaction.multipleChoice(
            id: 'mc',
            prompt: 'p',
            options: ['a', 'b', 'c'],
            correctIndex: 0,
          ),
          sourceFingerprint: 'fp',
        ),
        mode: StudyMode.review,
        ledgerOwner: StudyLedgerOwner.officialAnki,
        capabilities: StudyCapabilities.forMode(StudyMode.review),
      );
      final controller = StudySessionController(
        items: [item],
        ledgerResolver: StudyLedgerResolver(official: ledger),
      );
      await controller.start();
      controller.acceptPresentation(
        _receipt(
          item,
          controller,
          PresentationSide.question,
          renderer: PresentationRendererKind.flutterStructured,
        ),
      );
      await controller.submitObjectiveAnswer(correct: false);
      controller.acceptPresentation(
        _receipt(
          item,
          controller,
          PresentationSide.answer,
          renderer: PresentationRendererKind.flutterStructured,
        ),
      );
      await pumpEventQueue();
      expect(ledger.commits, 1);
      expect(ledger.outcomes.single, RecallOutcome.forgotten);
    });

    test('undo restores a single event', () async {
      final ledger = _FakeStudyLedger();
      final item = StudyItem(
        sessionItemId: 's1',
        courseId: courseId,
        placementId: 'p-1',
        cardKey: key(1),
        presentation: flipFor(key(1)),
        mode: StudyMode.review,
        ledgerOwner: StudyLedgerOwner.turnaFsrs,
        capabilities: StudyCapabilities.forMode(StudyMode.review),
      );
      final controller = StudySessionController(
        items: [item],
        ledgerResolver: StudyLedgerResolver(turna: ledger),
      );
      await controller.start();
      controller.acceptPresentation(_receipt(item, controller, PresentationSide.question));
      await controller.revealAnswer();
      controller.acceptPresentation(_receipt(item, controller, PresentationSide.answer));
      await controller.submitRecall(RecallOutcome.remembered);
      expect(await controller.undoLast(), isTrue);
      expect(ledger.undos, 1);
      expect(controller.rememberedCount, 0);
    });

    // Regression matrix for the undo index bug: the undone card must be
    // re-shown in EVERY timing, not just the end-of-session one. The old
    // index math only handled `completed`; after the production auto
    // continueNext the undone card was silently skipped, and in
    // readyForNext the decrement landed on the card BEFORE the undone one.
    for (final timing in _UndoTiming.values) {
      test('undo re-shows the undone card (${timing.name})', () async {
        final ledger = _FakeStudyLedger();
        final items = [
          for (var i = 1; i <= 3; i++)
            StudyItem(
              sessionItemId: 's$i',
              courseId: courseId,
              placementId: 'p-$i',
              cardKey: key(i),
              presentation: flipFor(key(i)),
              mode: StudyMode.review,
              ledgerOwner: StudyLedgerOwner.turnaFsrs,
              capabilities: StudyCapabilities.forMode(StudyMode.review),
            ),
        ];
        final controller = StudySessionController(
          items: items,
          ledgerResolver: StudyLedgerResolver(turna: ledger),
        );
        await controller.start();

        Future<void> answerCurrent() async {
          final item = controller.currentItem!;
          controller.acceptPresentation(
            _receipt(item, controller, PresentationSide.question),
          );
          await controller.revealAnswer();
          controller.acceptPresentation(
            _receipt(item, controller, PresentationSide.answer),
          );
          await controller.submitRecall(RecallOutcome.remembered);
        }

        switch (timing) {
          case _UndoTiming.readyForNext:
            await answerCurrent(); // s1 answered, not advanced yet
          case _UndoTiming.showingNextQuestion:
            await answerCurrent(); // s1 answered
            await controller.continueNext(); // now loading s2
          case _UndoTiming.completed:
            await answerCurrent(); // s1
            await controller.continueNext();
            await answerCurrent(); // s2
            await controller.continueNext();
            await answerCurrent(); // s3
            await controller.continueNext();
            expect(controller.phase, StudyCardPhase.completed);
        }
        // The receipt being undone always belongs to the LAST answered
        // card: s1 for the mid-session timings, s3 at completion.
        final expected =
            timing == _UndoTiming.completed ? 's3' : 's1';

        expect(await controller.undoLast(), isTrue);
        expect(ledger.undos, 1);
        expect(controller.phase, StudyCardPhase.loadingQuestion);
        expect(controller.currentItem!.sessionItemId, expected);
        // One remembered commit was rolled back; earlier answers stay.
        expect(
          controller.rememberedCount,
          timing == _UndoTiming.completed ? 2 : 0,
        );
      });
    }
  });
}

enum _UndoTiming { readyForNext, showingNextQuestion, completed }

PresentationReceipt _receipt(
  StudyItem item,
  StudySessionController controller,
  PresentationSide side, {
  PresentationRendererKind renderer = PresentationRendererKind.flutterFlip,
}) {
  return PresentationReceipt(
    cardKey: item.cardKey,
    generation: controller.generation,
    side: side,
    renderer: renderer,
    presentedAt: DateTime.now(),
  );
}

class _FakeStudyLedger implements StudyLedger {
  int commits = 0;
  int undos = 0;
  bool failOnce = false;
  final List<String> idempotencyKeys = [];
  final List<RecallOutcome> outcomes = [];
  final Map<String, StudyEventReceipt> _byKey = {};

  @override
  Future<DueSnapshot> dueSnapshot(StudyScope scope) async {
    return const DueSnapshot(dueCardKeys: {});
  }

  @override
  Future<SchedulePreview> preview(
    CanonicalCardKey key,
    RecallOutcome outcome,
  ) async {
    return const SchedulePreview(intervalLabel: '1d');
  }

  @override
  Future<StudyEventReceipt> commit(
    CanonicalCardKey key,
    RecallOutcome outcome, {
    required String idempotencyKey,
  }) async {
    if (failOnce) {
      failOnce = false;
      throw StateError('ledger unavailable');
    }
    final existing = _byKey[idempotencyKey];
    if (existing != null) return existing;
    commits++;
    idempotencyKeys.add(idempotencyKey);
    outcomes.add(outcome);
    final receipt = StudyEventReceipt(
      eventId: 'e-$commits',
      idempotencyKey: idempotencyKey,
      cardKey: key,
      ledgerOwner: StudyLedgerOwner.turnaFsrs,
      outcome: outcome,
      reviewedAt: DateTime.now(),
    );
    _byKey[idempotencyKey] = receipt;
    return receipt;
  }

  @override
  Future<bool> undo(StudyEventReceipt receipt) async {
    undos++;
    _byKey.remove(receipt.idempotencyKey);
    return true;
  }
}
