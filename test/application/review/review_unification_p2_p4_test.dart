import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/review/review_session_controller.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/domain/review/recall_outcome.dart';
import 'package:turna/domain/review/official_anki_review_ledger.dart';
import 'package:turna/domain/review/review_capabilities.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/review_ledger_resolver.dart';
import 'package:turna/domain/review/review_source.dart';
import 'package:turna/domain/review/turna_review_ledger.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P2 & P3: TurnaReviewLedger and Binary Recall', () {
    late SrsProvider srsProvider;
    late AppPrefs appPrefs;
    late TurnaReviewLedger ledger;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      appPrefs = AppPrefs(sp);
      await appPrefs.preferences.setString(LocalStateKeys.srsState, '{}');
      final linkStore = LessonLinkStore(appPrefs);
      final srsDao = emptySrsStateDao();
      srsProvider = SrsProvider(appPrefs, linkStore, srsDao);
      srsProvider.setSchedulerForTesting(const Sm2Engine());
      ledger = TurnaReviewLedger(srsProvider);
    });

    test('preview returns deterministic labels for forgotten and remembered',
        () async {
      srsProvider.registerWord('test-word-1');
      const key = ReviewSchedulingKey(
        rawId: 'test-word-1',
        source: TurnaCourseSource(),
      );

      final forgottenPreview =
          await ledger.preview(key, RecallOutcome.forgotten);
      final rememberedPreview =
          await ledger.preview(key, RecallOutcome.remembered);

      expect(forgottenPreview.intervalLabel, isNotEmpty);
      expect(rememberedPreview.intervalLabel, isNotEmpty);
    });

    test(
        'answer forgotten reduces interval / registers lapse and returns receipt',
        () async {
      srsProvider.registerWord('test-word-2');
      const key = ReviewSchedulingKey(
        rawId: 'test-word-2',
        source: TurnaCourseSource(),
      );

      final receipt = await ledger.answer(key, RecallOutcome.forgotten);

      expect(receipt.outcome, RecallOutcome.forgotten);
      expect(receipt.schedulingKey.rawId, 'test-word-2');

      final word = srsProvider.state['test-word-2']!;
      expect(word.lapses, 1);
    });

    test('answer remembered advances interval and returns receipt', () async {
      srsProvider.registerWord('test-word-3');
      const key = ReviewSchedulingKey(
        rawId: 'test-word-3',
        source: TurnaCourseSource(),
      );

      final receipt = await ledger.answer(key, RecallOutcome.remembered);

      expect(receipt.outcome, RecallOutcome.remembered);
      final word = srsProvider.state['test-word-3']!;
      expect(word.reps, 1);
      expect(word.lapses, 0);
    });

    test('undo safely rolls back previous word state using receipt snapshot',
        () async {
      final history = emptyReviewHistoryDao();
      srsProvider.setReviewHistoryDaoForTesting(history);
      srsProvider.registerWord('test-word-4');
      final initialWord = srsProvider.state['test-word-4']!;
      expect(initialWord.reps, 0);

      const key = ReviewSchedulingKey(
        rawId: 'test-word-4',
        source: TurnaCourseSource(),
      );

      final receipt = await ledger.answer(key, RecallOutcome.remembered);
      expect(srsProvider.state['test-word-4']!.reps, 1);
      final recorded = await history.eventsForCard('test-word-4');
      expect(recorded.single.sourceKey, receipt.eventId);

      final undoOk = await ledger.undo(receipt);
      expect(undoOk, isTrue);
      expect(srsProvider.state['test-word-4']!.reps, 0);
      expect(await history.eventsForCard('test-word-4'), isEmpty);
    });
  });

  group('P4: ReviewSessionController Flow', () {
    late SrsProvider srsProvider;
    late AppPrefs appPrefs;
    late TurnaReviewLedger turnaLedger;
    late ReviewLedgerResolver resolver;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      appPrefs = AppPrefs(sp);
      await appPrefs.preferences.setString(LocalStateKeys.srsState, '{}');
      final linkStore = LessonLinkStore(appPrefs);
      final srsDao = emptySrsStateDao();
      srsProvider = SrsProvider(appPrefs, linkStore, srsDao);
      srsProvider.setSchedulerForTesting(const Sm2Engine());
      turnaLedger = TurnaReviewLedger(srsProvider);
      resolver = ReviewLedgerResolver(turnaLedger: turnaLedger);
    });

    test('controller manages progression, reveals, answers, and completes',
        () async {
      srsProvider.registerWord('w1');
      srsProvider.registerWord('w2');

      final items = [
        const ReviewItem(
          sessionItemId: 'item-1',
          source: TurnaCourseSource(),
          content: StandardCourseCardContent(
            frontText: 'Merhaba',
            backText: 'Hello',
          ),
          capabilities: ReviewCapabilities.standardCourse,
          schedulingKey: ReviewSchedulingKey(
            rawId: 'w1',
            source: TurnaCourseSource(),
          ),
        ),
        const ReviewItem(
          sessionItemId: 'item-2',
          source: TurnaCourseSource(),
          content: StandardCourseCardContent(
            frontText: 'Teşekkürler',
            backText: 'Thank you',
          ),
          capabilities: ReviewCapabilities.standardCourse,
          schedulingKey: ReviewSchedulingKey(
            rawId: 'w2',
            source: TurnaCourseSource(),
          ),
        ),
      ];

      var completedCalled = false;
      final controller = ReviewSessionController(
        items: items,
        ledgerResolver: resolver,
        onSessionCompleted: (remembered, forgotten) async {
          completedCalled = true;
          expect(remembered, 1);
          expect(forgotten, 1);
        },
      );

      expect(controller.totalCount, 2);
      expect(controller.currentIndex, 0);
      expect(controller.isRevealed, isFalse);
      expect(controller.isComplete, isFalse);

      // Reveal card 1
      controller.reveal();
      expect(controller.isRevealed, isTrue);

      // Answer card 1 as remembered
      final ok1 = await controller.answer(RecallOutcome.remembered);
      expect(ok1, isTrue);
      expect(controller.currentIndex, 1);
      expect(controller.isRevealed, isFalse);
      expect(controller.rememberedCount, 1);

      // Reveal card 2
      controller.reveal();
      expect(controller.isRevealed, isTrue);

      // Answer card 2 as forgotten
      final ok2 = await controller.answer(RecallOutcome.forgotten);
      expect(ok2, isTrue);
      expect(controller.currentIndex, 2);
      expect(controller.isComplete, isTrue);
      expect(controller.forgottenCount, 1);
      expect(completedCalled, isTrue);
    });

    test('controller supports single-receipt undo', () async {
      srsProvider.registerWord('undo-word');
      final items = [
        const ReviewItem(
          sessionItemId: 'item-undo',
          source: TurnaCourseSource(),
          content: StandardCourseCardContent(
            frontText: 'Evet',
            backText: 'Yes',
          ),
          capabilities: ReviewCapabilities.standardCourse,
          schedulingKey: ReviewSchedulingKey(
            rawId: 'undo-word',
            source: TurnaCourseSource(),
          ),
        ),
      ];

      final controller = ReviewSessionController(
        items: items,
        ledgerResolver: resolver,
      );

      controller.reveal();
      await controller.answer(RecallOutcome.remembered);
      expect(controller.currentIndex, 1);
      expect(controller.rememberedCount, 1);
      expect(srsProvider.state['undo-word']!.reps, 1);

      // Undo
      final undone = await controller.undoLast();
      expect(undone, isTrue);
      expect(controller.currentIndex, 0);
      expect(controller.rememberedCount, 0);
      expect(srsProvider.state['undo-word']!.reps, 0);
    });
  });

  group('P2: Official ledger commit contract', () {
    const flags = OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
      renderer: true,
      scheduler: true,
    );

    test('wrong phase and wrong card never return a success receipt', () async {
      final engine = FakeOfficialAnkiEngine();
      engine.seedPackage(packagePath: 'ledger.apkg', notes: 2, cards: 2);
      final session = OfficialReviewSession(engine: engine, flags: flags);
      await session.openDeck(1);
      final cardId = session.current!.cardId;
      final ledger = OfficialAnkiReviewLedger(session);
      final source = OfficialAnkiSource(
        sourceId: 'source',
        deckId: 1,
        cardId: cardId,
      );
      final key = ReviewSchedulingKey(rawId: '$cardId', source: source);

      await expectLater(
        ledger.answer(key, RecallOutcome.remembered),
        throwsA(
          isA<OfficialAnkiException>().having(
            (error) => error.code,
            'code',
            OfficialAnkiErrorCode.invalidState,
          ),
        ),
      );
      expect(engine.officialAnswers, 0);

      session.showAnswer();
      final staleSource = OfficialAnkiSource(
        sourceId: 'source',
        deckId: 1,
        cardId: cardId + 99,
      );
      final staleKey = ReviewSchedulingKey(
        rawId: '${cardId + 99}',
        source: staleSource,
      );
      await expectLater(
        ledger.answer(staleKey, RecallOutcome.forgotten),
        throwsA(
          isA<OfficialAnkiException>().having(
            (error) => error.code,
            'code',
            OfficialAnkiErrorCode.schedulingContextStale,
          ),
        ),
      );
      expect(engine.officialAnswers, 0);
    });

    test('binary answer returns scheduler mutation receipt and undo uses it',
        () async {
      final engine = FakeOfficialAnkiEngine();
      engine.seedPackage(packagePath: 'ledger.apkg', notes: 2, cards: 2);
      final session = OfficialReviewSession(engine: engine, flags: flags);
      await session.openDeck(1);
      final cardId = session.current!.cardId;
      session.showAnswer();
      final ledger = OfficialAnkiReviewLedger(session);
      final source = OfficialAnkiSource(
        sourceId: 'source',
        deckId: 1,
        cardId: cardId,
      );
      final receipt = await ledger.answer(
        ReviewSchedulingKey(rawId: '$cardId', source: source),
        RecallOutcome.remembered,
      );

      expect(engine.officialAnswers, 1);
      expect(receipt.eventId, engine.lastClientMutationId);
      expect(receipt.outcome, RecallOutcome.remembered);
      expect(await ledger.undo(receipt), isTrue);
      expect(engine.officialUndos, 1);
      expect(await ledger.undo(receipt), isFalse);
    });
  });
}
