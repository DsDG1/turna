// Unit tests for [ReviewHistoryDao]: insert/query round-trip, ordering,
// prefix delete, and the `recalled` derivation.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/domain/course/srs_word.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReviewHistoryDao dao;

  setUp(() {
    dao = emptyReviewHistoryDao();
  });

  ReviewEventRecord makeEvent({
    required String cardId,
    required int quality,
    DateTime? reviewedAt,
    int prevInterval = 1,
    int nextInterval = 4,
    String queue = 'srs',
  }) {
    return ReviewEventRecord(
      cardId: cardId,
      queue: queue,
      reviewedAt: reviewedAt ?? DateTime(2026, 7, 28, 12),
      quality: quality,
      prevIntervalDays: prevInterval,
      nextIntervalDays: nextInterval,
      prevEase: 2.5,
      nextEase: 2.5,
      reps: 1,
      lapses: 0,
      type: SrsItemType.word,
    );
  }

  group('ReviewHistoryDao', () {
    test('count is zero on an empty table', () async {
      expect(await dao.count(), 0);
    });

    test('insertEvent then eventsForCard round-trips fields', () async {
      final at = DateTime(2026, 7, 28, 9, 15);
      await dao.insertEvent(makeEvent(
        cardId: 'w-1',
        quality: 4,
        reviewedAt: at,
        prevInterval: 1,
        nextInterval: 4,
      ));

      final events = await dao.eventsForCard('w-1');
      expect(events, hasLength(1));
      final e = events.single;
      expect(e.cardId, 'w-1');
      expect(e.queue, 'srs');
      expect(e.quality, 4);
      expect(e.recalled, isTrue);
      expect(e.prevIntervalDays, 1);
      expect(e.nextIntervalDays, 4);
      expect(e.reps, 1);
      expect(e.type, SrsItemType.word);
      expect(e.reviewedAt, at);
    });

    test('eventsForCard returns oldest first', () async {
      await dao.insertEvent(makeEvent(
          cardId: 'w-1', quality: 1, reviewedAt: DateTime(2026, 7, 1)));
      await dao.insertEvent(makeEvent(
          cardId: 'w-1', quality: 4, reviewedAt: DateTime(2026, 7, 2)));
      await dao.insertEvent(makeEvent(
          cardId: 'w-1', quality: 4, reviewedAt: DateTime(2026, 7, 3)));

      final events = await dao.eventsForCard('w-1');
      expect(events.map((e) => e.quality), [1, 4, 4]);
    });

    test('failed recall (quality < 3) is not recalled', () async {
      await dao.insertEvent(makeEvent(cardId: 'w-1', quality: 1));
      expect((await dao.eventsForCard('w-1')).single.recalled, isFalse);
    });

    test('insertBatch writes many rows', () async {
      await dao.insertBatch([
        makeEvent(cardId: 'w-1', quality: 4),
        makeEvent(cardId: 'w-2', quality: 1),
        makeEvent(cardId: 'w-3', quality: 4),
      ]);
      expect(await dao.count(), 3);
    });

    test('recentEvents returns newest first with limit', () async {
      for (var i = 1; i <= 5; i++) {
        await dao.insertEvent(makeEvent(
          cardId: 'w-$i',
          quality: 4,
          reviewedAt: DateTime(2026, 7, i),
        ));
      }
      final recent = await dao.recentEvents(limit: 3);
      expect(recent.map((e) => e.cardId), ['w-5', 'w-4', 'w-3']);
    });

    test('allEvents is sorted by cardId then time', () async {
      await dao.insertEvent(makeEvent(
          cardId: 'w-2', quality: 4, reviewedAt: DateTime(2026, 7, 1)));
      await dao.insertEvent(makeEvent(
          cardId: 'w-1', quality: 4, reviewedAt: DateTime(2026, 7, 2)));
      await dao.insertEvent(makeEvent(
          cardId: 'w-1', quality: 1, reviewedAt: DateTime(2026, 7, 1)));
      final all = await dao.allEvents();
      expect(all.map((e) => '${e.cardId}:${e.quality}').toList(),
          ['w-1:1', 'w-1:4', 'w-2:4']);
    });

    test('deleteByCardPrefix removes only matching cards', () async {
      await dao.insertBatch([
        makeEvent(cardId: 'anki-imp1-n1', quality: 4),
        makeEvent(cardId: 'anki-imp1-n2', quality: 1),
        makeEvent(cardId: 'anki-imp2-n1', quality: 4),
        makeEvent(cardId: 'w-builtin', quality: 4),
      ]);
      await dao.deleteByCardPrefix('anki-imp1-');
      expect(await dao.count(), 2);
      final all = await dao.allEvents();
      expect(all.map((e) => e.cardId).toSet(), {'anki-imp2-n1', 'w-builtin'});
    });
  });
}
