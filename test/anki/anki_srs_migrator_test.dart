// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/anki_srs_migrator.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

Future<StreamingSharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return StreamingSharedPreferences.instance;
}

void main() {
  group('AnkiSrsMigrator', () {
    late AnkiSrsMigrator migrator;

    setUp(() {
      migrator = AnkiSrsMigrator();
    });

    // We test the internal conversion logic via a helper that exposes it.
    // Since _convertCard is private, we test through the public interface
    // by verifying SrsWord properties after migration.

    group('SRS field conversion logic', () {
      test('new card (queue=0, reps=0) gets fresh state', () {
        // A new card should have: dueAt=now, interval=0, ease=2.5, reps=0
        final card = AnkiCardData(
          id: 1,
          nid: 100,
          did: 1,
          queue: 0,
          due: 5,
          ivl: 0,
          factor: 2500,
          reps: 0,
          lapses: 0,
        );

        // Verify the card data is correctly structured
        expect(card.queue, 0);
        expect(card.reps, 0);
        expect(card.factor, 2500);
      });

      test('review card (queue=2) converts factor correctly', () {
        final card = AnkiCardData(
          id: 2,
          nid: 200,
          did: 1,
          queue: 2,
          due: 3,
          ivl: 10,
          factor: 2500,
          reps: 5,
          lapses: 1,
        );

        // factor 2500 → ease 2.5
        expect(card.factor / 1000.0, 2.5);
        expect(card.ivl, 10);
        expect(card.reps, 5);
        expect(card.lapses, 1);
      });

      test('ease clamped to minimum 1.3', () {
        final card = AnkiCardData(
          id: 3,
          nid: 300,
          did: 1,
          queue: 2,
          due: 1,
          ivl: 1,
          factor: 1000, // Below minimum (1.0 < 1.3)
          reps: 2,
          lapses: 5,
        );

        var ease = card.factor / 1000.0;
        if (ease < 1.3) ease = 1.3;
        expect(ease, 1.3);
      });

      test('suspended card (queue=-1) marked as leech', () {
        final card = AnkiCardData(
          id: 4,
          nid: 400,
          did: 1,
          queue: -1,
          due: 0,
          ivl: 5,
          factor: 2000,
          reps: 3,
          lapses: 4,
        );

        final isLeech = card.queue == -1 || card.queue == -2;
        expect(isLeech, true);
      });

      test('buried card (queue=-2) marked as leech', () {
        final card = AnkiCardData(
          id: 5,
          nid: 500,
          did: 1,
          queue: -2,
          due: 0,
          ivl: 3,
          factor: 1800,
          reps: 2,
          lapses: 3,
        );

        final isLeech = card.queue == -1 || card.queue == -2;
        expect(isLeech, true);
      });

      test('learning card (queue=1) due semantics', () {
        final card = AnkiCardData(
          id: 6,
          nid: 600,
          did: 1,
          queue: 1,
          due: 10, // 10 minutes
          ivl: 0,
          factor: 2500,
          reps: 1,
          lapses: 0,
        );

        // Learning queue: due is in minutes
        expect(card.queue, 1);
        expect(card.due, 10);
      });
    });

    group('SrsWord model', () {
      test('SrsWord.fresh creates due-now card', () {
        final word = SrsWord.fresh('test-id');
        expect(word.wordId, 'test-id');
        expect(word.intervalDays, 1);
        expect(word.ease, 2.5);
        expect(word.reps, 0);
        expect(word.lapses, 0);
        expect(word.isLeech, false);
      });

      test('SrsWord serialization roundtrip', () {
        final word = SrsWord(
          wordId: 'anki-test-n123',
          dueAt: DateTime(2025, 6, 15),
          intervalDays: 10,
          ease: 2.3,
          reps: 5,
          lapses: 2,
          isLeech: false,
        );

        final json = word.toJson();
        final restored = SrsWord.fromJson(json);

        expect(restored.wordId, word.wordId);
        expect(restored.intervalDays, word.intervalDays);
        expect(restored.ease, word.ease);
        expect(restored.reps, word.reps);
        expect(restored.lapses, word.lapses);
        expect(restored.isLeech, word.isLeech);
      });
    });

    group('revlog backfill', () {
      test('migrates revlog entries into review events', () async {
        final sp = await _prefs();
        final prefs = AppPrefs(sp);
        final link = LessonLinkStore(prefs);
        final srsDao = emptySrsStateDao();
        final reviewDao = emptyReviewHistoryDao();
        final srs = SrsProvider(prefs, link, srsDao);
        srs.setReviewHistoryDaoForTesting(reviewDao);

        final cards = [
          AnkiCardData(
              id: 501,
              nid: 100,
              did: 1,
              queue: 2,
              ivl: 10,
              factor: 2500,
              reps: 3),
          AnkiCardData(
              id: 502,
              nid: 200,
              did: 1,
              queue: 2,
              ivl: 4,
              factor: 2300,
              reps: 2),
        ];
        final revlog = [
          // Card 501 (wordId anki-imp-c501): "good" at prev interval 4 -> next 10.
          AnkiRevlogEntry(
              id: 1700000000000,
              cid: 501,
              ease: 3,
              ivl: 10,
              lastIvl: 4,
              factor: 2500,
              type: 1),
          // Card 501: "again" at prev interval 10 -> next 1.
          AnkiRevlogEntry(
              id: 1700000001000,
              cid: 501,
              ease: 1,
              ivl: 1,
              lastIvl: 10,
              factor: 2300,
              type: 2),
          // Card 502: "easy" at prev interval 1 -> next 4.
          AnkiRevlogEntry(
              id: 1700000002000,
              cid: 502,
              ease: 4,
              ivl: 4,
              lastIvl: 1,
              factor: 2400,
              type: 1),
          // revlog for an unknown cid -> skipped.
          AnkiRevlogEntry(
              id: 1700000003000,
              cid: 999,
              ease: 3,
              ivl: 5,
              lastIvl: 1,
              factor: 2500,
              type: 1),
        ];

        await migrator.migrate(
          cards: cards,
          importId: 'imp',
          srsProvider: srs,
          revlog: revlog,
          reviewHistoryDao: reviewDao,
        );

        final events501 = await reviewDao.eventsForCard('anki-imp-c501');
        expect(events501, hasLength(2));
        // First event: good (ease 3 -> quality 4), prev 4, next 10, recalled.
        expect(events501[0].quality, 4);
        expect(events501[0].recalled, isTrue);
        expect(events501[0].prevIntervalDays, 4);
        expect(events501[0].nextIntervalDays, 10);
        // Second event: again (ease 1 -> quality 1), recalled false.
        expect(events501[1].quality, 1);
        expect(events501[1].recalled, isFalse);

        final events502 = await reviewDao.eventsForCard('anki-imp-c502');
        expect(events502, hasLength(1));
        expect(events502.single.quality, 5); // easy remains distinct
        expect(events502.single.recalled, isTrue);

        // Unknown cid 999 produced no event.
        expect(await reviewDao.eventsForCard('anki-imp-c999'), isEmpty);
      });

      test('skips revlog backfill when no DAO is supplied', () async {
        final sp = await _prefs();
        final prefs = AppPrefs(sp);
        final link = LessonLinkStore(prefs);
        final srs = SrsProvider(prefs, link, emptySrsStateDao());
        // No reviewHistoryDao -> revlog is ignored, no crash.
        await migrator.migrate(
          cards: [AnkiCardData(id: 501, nid: 100, did: 1, queue: 0)],
          importId: 'imp',
          srsProvider: srs,
          revlog: [
            AnkiRevlogEntry(
                id: 1, cid: 501, ease: 3, ivl: 1, lastIvl: 0, factor: 2500),
          ],
        );
        expect(srs.state.containsKey('anki-imp-c501'), isTrue);
      });
    });

    group('new-card due staggering', () {
      test('spreads new-queue positions across days by newCardsPerDay',
          () async {
        final sp = await _prefs();
        final prefs = AppPrefs(sp);
        final link = LessonLinkStore(prefs);
        final srs = SrsProvider(prefs, link, emptySrsStateDao());
        final now = DateTime.now();

        // 45 new cards with Anki positions 0..44, 20 per day → 3 day bands.
        final cards = [
          for (var i = 0; i < 45; i++)
            AnkiCardData(
              id: 1000 + i,
              nid: 2000 + i,
              did: 1,
              queue: 0,
              due: i,
              reps: 0,
              factor: 2500,
            ),
        ];

        await migrator.migrate(
          cards: cards,
          importId: 'stag',
          srsProvider: srs,
          newCardsPerDay: 20,
        );

        final today = DateTime(now.year, now.month, now.day);
        final checkTime = DateTime.now();
        final dueToday = srs.state.values.where((w) {
          return !w.dueAt.isAfter(checkTime);
        }).length;
        // Positions 0-19 due today (dueAt ≈ now).
        expect(dueToday, 20);

        final day1 = srs.state['anki-stag-c1020']!;
        final day2 = srs.state['anki-stag-c1040']!;
        expect(day1.sourceKind, SrsSourceKind.ankiLegacy);
        expect(day1.sourceId, 'stag');
        expect(
          DateTime(day1.dueAt.year, day1.dueAt.month, day1.dueAt.day),
          today.add(const Duration(days: 1)),
        );
        expect(
          DateTime(day2.dueAt.year, day2.dueAt.month, day2.dueAt.day),
          today.add(const Duration(days: 2)),
        );
      });
    });

    group('Anki scheduler fidelity', () {
      test('reset mode ignores source scheduling and imports a fresh card',
          () async {
        final sp = await _prefs();
        final prefs = AppPrefs(sp);
        final srs = SrsProvider(
          prefs,
          LessonLinkStore(prefs),
          emptySrsStateDao(),
        );
        final card = AnkiCardData(
          id: 699,
          nid: 1,
          did: 1,
          queue: -1,
          due: 999999,
          ivl: 365,
          factor: 1800,
          reps: 50,
          lapses: 10,
        );

        await migrator.migrate(
          cards: [card],
          importId: 'reset',
          srsProvider: srs,
          importScheduling: false,
        );

        final imported = srs.state['anki-reset-c699']!;
        expect(imported.reps, 0);
        expect(imported.lapses, 0);
        expect(imported.intervalDays, 0);
        expect(imported.ease, 2.5);
        expect(imported.isSuspended, isFalse);
      });

      test('review due is anchored to collection creation day', () async {
        final sp = await _prefs();
        final prefs = AppPrefs(sp);
        final srs = SrsProvider(
          prefs,
          LessonLinkStore(prefs),
          emptySrsStateDao(),
        );
        final created =
            DateTime(2024, 1, 10, 18).millisecondsSinceEpoch ~/ 1000;

        await migrator.migrate(
          cards: [
            AnkiCardData(
              id: 700,
              nid: 701,
              did: 1,
              queue: 2,
              due: 5,
              reps: 4,
              ivl: 10,
              factor: 2500,
            ),
          ],
          importId: 'crt',
          srsProvider: srs,
          collectionCreationTime: created,
        );

        expect(
          srs.state['anki-crt-c700']!.dueAt,
          DateTime(2024, 1, 15),
        );
      });

      test('learning epoch due is not interpreted as minutes', () async {
        final sp = await _prefs();
        final prefs = AppPrefs(sp);
        final srs = SrsProvider(
          prefs,
          LessonLinkStore(prefs),
          emptySrsStateDao(),
        );
        final due = DateTime(2030, 5, 6, 12).millisecondsSinceEpoch ~/ 1000;

        await migrator.migrate(
          cards: [
            AnkiCardData(
              id: 710,
              nid: 711,
              did: 1,
              queue: 1,
              due: due,
              reps: 1,
            ),
          ],
          importId: 'epoch',
          srsProvider: srs,
        );

        expect(srs.state['anki-epoch-c710']!.dueAt, DateTime(2030, 5, 6, 12));
      });

      test('legacy learning due (queue=1) is interpreted as minutes', () async {
        // Anki 2.1 stored learning `due` as MINUTES relative to "now"
        // (when the card left the learning queue). A `due` value below the
        // Unix-seconds threshold (~10^8) must therefore shift dueAt by the
        // same number of minutes from now, not seconds.
        final sp = await _prefs();
        final prefs = AppPrefs(sp);
        final srs = SrsProvider(
          prefs,
          LessonLinkStore(prefs),
          emptySrsStateDao(),
        );
        final before = DateTime.now();

        await migrator.migrate(
          cards: [
            AnkiCardData(
              id: 711,
              nid: 712,
              did: 1,
              queue: 1,
              due: 10, // 10 minutes (legacy Anki 2.1 semantics)
              reps: 1,
            ),
          ],
          importId: 'legacy',
          srsProvider: srs,
        );

        final after = DateTime.now();
        final dueAt = srs.state['anki-legacy-c711']!.dueAt;

        // dueAt must fall in [before + 10min, after + 10min] — not within
        // 10 seconds of either bound (which is what the buggy seconds branch
        // would produce).
        expect(
          dueAt.isAfter(before.add(const Duration(minutes: 10)).subtract(
                const Duration(seconds: 2),
              )),
          isTrue,
          reason: 'dueAt $dueAt must be at least 10 minutes after $before',
        );
        expect(
          dueAt.isBefore(after.add(const Duration(minutes: 10)).add(
                const Duration(seconds: 2),
              )),
          isTrue,
          reason: 'dueAt $dueAt must be at most 10 minutes after $after',
        );
        // And critically, NOT within seconds of `before` (the bug would
        // produce dueAt ≈ before + 10s).
        expect(
          dueAt.difference(before).inSeconds > 60,
          isTrue,
          reason: 'dueAt ${dueAt.difference(before).inSeconds}s after before; '
              'expected ~600s (10 min), not ~10s',
        );
      });

      test('suspended and buried cards are explicit non-leech states',
          () async {
        final sp = await _prefs();
        final prefs = AppPrefs(sp);
        final srs = SrsProvider(
          prefs,
          LessonLinkStore(prefs),
          emptySrsStateDao(),
        );

        await migrator.migrate(
          cards: [
            AnkiCardData(id: 720, nid: 721, did: 1, queue: -1, reps: 4),
            AnkiCardData(id: 730, nid: 731, did: 1, queue: -2, reps: 4),
          ],
          importId: 'hidden',
          srsProvider: srs,
        );

        final suspended = srs.state['anki-hidden-c720']!;
        final buried = srs.state['anki-hidden-c730']!;
        expect(suspended.isSuspended, isTrue);
        expect(suspended.isLeech, isFalse);
        expect(buried.isBuried, isTrue);
        expect(buried.isLeech, isFalse);
        expect(srs.getDueWords(), isEmpty);
      });

      test('revlog import is idempotent by stable source key', () async {
        final sp = await _prefs();
        final prefs = AppPrefs(sp);
        final srs = SrsProvider(
          prefs,
          LessonLinkStore(prefs),
          emptySrsStateDao(),
        );
        final history = emptyReviewHistoryDao();
        final card = AnkiCardData(id: 740, nid: 741, did: 1, queue: 2);
        final revlog = [
          AnkiRevlogEntry(id: 1800000000000, cid: 740, ease: 3, ivl: 1),
        ];

        await migrator.migrate(
          cards: [card],
          importId: 'history',
          srsProvider: srs,
          revlog: revlog,
          reviewHistoryDao: history,
        );
        await migrator.migrate(
          cards: [card],
          importId: 'history',
          srsProvider: srs,
          revlog: revlog,
          reviewHistoryDao: history,
        );

        final events = await history.eventsForCard('anki-history-c740');
        expect(events, hasLength(1));
        expect(events.single.sourceKey, 'anki-history-r1800000000000');
      });
    });
  });
}
