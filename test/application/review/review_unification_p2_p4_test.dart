import 'dart:async';

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
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/domain/review/recall_outcome.dart';
import 'package:turna/application/anki_official/review/official_anki_review_ledger.dart';
import 'package:turna/domain/review/review_capabilities.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/review_ledger.dart';
import 'package:turna/application/review/review_ledger_resolver.dart';
import 'package:turna/domain/review/review_source.dart';
import 'package:turna/domain/review/srs_scheduling_gateway.dart';
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

    test('answer reuses cachedPreview without a second preview call', () async {
      srsProvider.registerWord('test-word-cached');
      const key = ReviewSchedulingKey(
        rawId: 'test-word-cached',
        source: TurnaCourseSource(),
      );
      final cached = await ledger.preview(key, RecallOutcome.forgotten);
      final receipt = await ledger.answer(
        key,
        RecallOutcome.forgotten,
        cachedPreview: cached,
      );
      expect(receipt.preview.intervalLabel, cached.intervalLabel);
      expect(srsProvider.state['test-word-cached']!.lapses, 1);
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

    test('retryPreviews recovers a failed preview load', () async {
      // 'missing-word' is deliberately unregistered: preview throws for
      // unknown ids, which used to leave the session stuck on lastError.
      final items = [
        const ReviewItem(
          sessionItemId: 'item-missing',
          source: TurnaCourseSource(),
          content: StandardCourseCardContent(
            frontText: 'Kelime',
            backText: 'Word',
          ),
          capabilities: ReviewCapabilities.standardCourse,
          schedulingKey: ReviewSchedulingKey(
            rawId: 'missing-word',
            source: TurnaCourseSource(),
          ),
        ),
      ];

      final controller = ReviewSessionController(
        items: items,
        ledgerResolver: resolver,
      );
      // Let the constructor's async preview load settle into lastError.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.lastError, isNotNull);

      // Once the underlying cause is fixed, retry reloads and clears it.
      srsProvider.registerWord('missing-word');
      await controller.retryPreviews();
      expect(controller.lastError, isNull);
      expect(controller.rememberedPreview, isNotNull);
    });

    test('last card stays current until persist settles', () async {
      final ledger = _GatedTurnaLedger();
      final controller = ReviewSessionController(
        items: [_lastCardItem('w1')],
        ledgerResolver: ReviewLedgerResolver(turnaLedger: ledger),
      );
      controller.reveal();
      final pending = controller.answer(RecallOutcome.remembered);
      expect(controller.isComplete, isFalse);
      expect(controller.isPersisting, isTrue);
      expect(controller.currentIndex, 0);
      expect(controller.currentItem?.schedulingKey.rawId, 'w1');
      expect(controller.isRevealed, isTrue);

      ledger.gate.complete();
      expect(await pending, isTrue);
      expect(controller.isComplete, isTrue);
      expect(controller.currentIndex, 1);
    });

    test('last-card write failure stays retryable and does not complete',
        () async {
      final ledger = _GatedTurnaLedger()..failWrite = true;
      var completed = false;
      final controller = ReviewSessionController(
        items: [_lastCardItem('w1')],
        ledgerResolver: ReviewLedgerResolver(turnaLedger: ledger),
        onSessionCompleted: (_, __) async => completed = true,
      );
      controller.reveal();
      final pending = controller.answer(RecallOutcome.remembered);
      ledger.gate.complete();
      expect(await pending, isFalse);
      expect(controller.isComplete, isFalse);
      expect(controller.writeError, isNotNull);
      expect(completed, isFalse);
      expect(await controller.undoLast(), isFalse);
      expect(controller.lastReceipt, isNull);
      expect(controller.currentIndex, 0);
    });

    test('retryWrite after last-card failure completes and settles', () async {
      final ledger = _GatedTurnaLedger()..failWrite = true;
      var completed = false;
      final controller = ReviewSessionController(
        items: [_lastCardItem('w1')],
        ledgerResolver: ReviewLedgerResolver(turnaLedger: ledger),
        onSessionCompleted: (_, __) async => completed = true,
      );
      controller.reveal();
      ledger.gate.complete();
      expect(await controller.answer(RecallOutcome.remembered), isFalse);
      expect(completed, isFalse);

      ledger.failWrite = false;
      ledger.gate = Completer<void>()..complete();
      expect(await controller.retryWrite(), isTrue);
      expect(controller.isComplete, isTrue);
      expect(controller.writeError, isNull);
      expect(completed, isTrue);
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

ReviewItem _lastCardItem(String id) => ReviewItem(
      sessionItemId: 'item-$id',
      source: const TurnaCourseSource(),
      content: StandardCourseCardContent(
        frontText: id,
        backText: id,
      ),
      capabilities: ReviewCapabilities.standardCourse,
      schedulingKey: ReviewSchedulingKey(
        rawId: id,
        source: const TurnaCourseSource(),
      ),
    );

class _UnusedGateway implements SrsSchedulingGateway {
  @override
  Map<String, SrsWord> get state => {};
  @override
  int get dueCount => 0;
  @override
  int get expressionDueCount => 0;
  @override
  List<SrsWord> getDueAnkiWords([DateTime? now]) => const [];
  @override
  int previewOutcomeDays(SrsWord word, ReviewOutcome outcome) => 1;
  @override
  Future<int?> previewFailMinutesFor(SrsWord word, {DateTime? now}) async => 10;
  @override
  Future<SrsWord?> reviewWordOutcome(String wordId, ReviewOutcome outcome,
          {String? eventSourceKey}) async =>
      null;
  @override
  Future<SrsWord?> reviewExpressionOutcome(
          String expressionId, ReviewOutcome outcome,
          {String? eventSourceKey}) async =>
      null;
  @override
  Future<bool> rollbackWord(String wordId, SrsWord? previous,
          {String? eventSourceKey}) async =>
      true;
  @override
  Future<bool> rollbackExpression(String expressionId, SrsWord? previous,
          {String? eventSourceKey}) async =>
      true;
}

class _GatedTurnaLedger extends TurnaReviewLedger {
  _GatedTurnaLedger() : super(_UnusedGateway());

  Completer<void> gate = Completer<void>();
  bool failWrite = false;

  @override
  Future<ReviewPreview> preview(
    ReviewSchedulingKey key,
    RecallOutcome outcome,
  ) async {
    return const ReviewPreview(intervalLabel: '1d');
  }

  @override
  Future<ReviewEventReceipt> answer(
    ReviewSchedulingKey key,
    RecallOutcome outcome, {
    int durationMs = 0,
    ReviewPreview? cachedPreview,
  }) async {
    await gate.future;
    if (failWrite) throw StateError('write failed');
    return ReviewEventReceipt(
      eventId: 'evt-${key.rawId}',
      source: key.source,
      schedulingKey: key,
      outcome: outcome,
      reviewedAt: DateTime.now(),
      preview: cachedPreview ?? const ReviewPreview(intervalLabel: '1d'),
    );
  }

  @override
  Future<bool> undo(ReviewEventReceipt receipt) async => true;
}
