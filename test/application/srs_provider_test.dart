// Unit tests for SrsProvider plumbing: registration, due computation, and the
// word/expression dual-track. Scheduling assertions use SM-2 via
// [setSchedulerForTesting] so intervals stay deterministic; production default
// is FSRS (ADR 0028, covered by test/core/fsrs_engine_test.dart).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

/// A [ReviewHistoryDao] whose `countFailsOnLocalDay` resolves only when the
/// test completes [_failCountFuture]. Used to keep [SrsQueueProvider.reviewItem]
/// suspended on its fail-path await so the in-flight undo gate can be exercised.
class _ControllableReviewHistoryDao implements ReviewHistoryDao {
  _ControllableReviewHistoryDao(this._failCountFuture);
  final Future<int> _failCountFuture;

  @override
  Future<int> countFailsOnLocalDay(String cardId, DateTime day) =>
      _failCountFuture;

  @override
  Future<void> insertEvent(ReviewEventRecord event) async {}

  @override
  Future<bool> deleteLatestForCard(String cardId) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late LessonLinkStore linkStore;
  late SrsStateDao dao;
  late SrsProvider srs;

  setUp(() async {
    // setMockInitialValues does not clear an already-cached
    // StreamingSharedPreferences instance, so reset the SRS key explicitly
    // between tests to avoid cross-test state leakage.
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.preferences.setString(LocalStateKeys.srsState, '{}');
    linkStore = LessonLinkStore(prefs);
    dao = emptySrsStateDao();
    srs = SrsProvider(prefs, linkStore, dao);
    // Keep provider tests on SM-2 so interval expectations stay fixed.
    srs.setSchedulerForTesting(const Sm2Engine());
  });

  SrsWord registeredWord(String id) => srs.state[id]!;

  group('registration', () {
    test('registerWord creates a fresh (immediately-due) word entry', () {
      srs.registerWord('w-1');
      final word = registeredWord('w-1');
      expect(word.type, SrsItemType.word);
      expect(word.reps, 0);
      expect(word.intervalDays, 1);
      expect(word.lapses, 0);
      expect(srs.totalRegistered, 1);
    });

    test('registerWord is idempotent — re-registering does not reset state',
        () {
      srs.registerWord('w-1');
      // Mutate state by reviewing.
      srs.reviewWord('w-1', ReviewGrade.known.sm2);
      final before = registeredWord('w-1');

      srs.registerWord('w-1'); // no-op
      final after = registeredWord('w-1');

      expect(after.reps, before.reps);
      expect(after.intervalDays, before.intervalDays);
    });

    test('registerExpression tags the entry with the expression type', () {
      srs.registerExpression('e-1');
      final expr = srs.state['e-1']!;
      expect(expr.type, SrsItemType.expression);
      expect(srs.expressionTotalRegistered, 1);
      expect(srs.totalRegistered, 0); // words only
    });

    test('registerAll registers every unseen word and skips seen ones', () {
      srs.registerWord('w-1');
      srs.registerAll(['w-1', 'w-2', 'w-3']);
      expect(srs.state.keys.toSet(), {'w-1', 'w-2', 'w-3'});
    });
  });

  group('SM-2 review', () {
    test('a successful first review grows the interval to 1 day and reps to 1',
        () async {
      srs.registerWord('w-1');
      final updated = await srs.reviewWord('w-1', ReviewGrade.known.sm2);
      expect(updated, isNotNull);
      expect(updated!.reps, 1);
      expect(updated.intervalDays, 1);
      expect(updated.lapses, 0);
      expect(updated.dueAt.isAfter(DateTime.now()), isTrue);
    });

    test('a second successful review grows the interval to 4 days', () async {
      srs.registerWord('w-1');
      await srs.reviewWord('w-1', ReviewGrade.known.sm2);
      final updated = await srs.reviewWord('w-1', ReviewGrade.known.sm2);
      expect(updated!.reps, 2);
      expect(updated.intervalDays, 4);
    });

    test('a failed review counts a lapse and re-dues for same-day relearn',
        () async {
      srs.registerWord('w-1');
      await srs.reviewWord('w-1', ReviewGrade.known.sm2);
      final updated = await srs.reviewWord('w-1', ReviewGrade.unknown.sm2);
      // reps counts total successes and is preserved across lapses.
      expect(updated!.reps, 1);
      expect(updated.lapses, 1);
      expect(updated.intervalDays, 1);
      // Failed cards reappear in ~10 minutes, not tomorrow.
      expect(updated.dueAt.isAfter(DateTime.now()), isTrue);
      final diff = updated.dueAt.difference(DateTime.now());
      expect(diff.inMinutes, lessThanOrEqualTo(Sm2Engine.relearnDelayMinutes));
    });

    test('reviewWord on an unknown id returns null', () async {
      expect(await srs.reviewWord('missing', ReviewGrade.known.sm2), isNull);
    });

    test('reviewWithQuality maps the 4-button grade to SM-2 quality', () async {
      srs.registerWord('w-1');
      final viaQuality = await srs.reviewWithQuality('w-1', ReviewGrade.known);
      expect(viaQuality, isNotNull);
      expect(viaQuality!.reps, 1);
      // A second review via the SM-2 quality int should advance identically.
      final viaSm2 = await srs.reviewWord('w-1', ReviewGrade.known.sm2);
      expect(viaSm2!.reps, 2);
    });

    test('expression review goes through the expression queue', () async {
      srs.registerExpression('e-1');
      final updated = await srs.reviewExpression('e-1', ReviewGrade.known.sm2);
      expect(updated, isNotNull);
      expect(updated!.type, SrsItemType.expression);
      expect(updated.reps, 1);
    });
  });

  group('due computation', () {
    test('fresh words are due immediately', () {
      srs.registerWord('w-1');
      srs.registerWord('w-2');
      final due = srs.getDueWords(DateTime.now());
      expect(due.map((w) => w.wordId).toSet(), {'w-1', 'w-2'});
    });

    test('reviewed words scheduled in the future are not due', () async {
      srs.registerWord('w-1');
      // good review → interval 1 day, due tomorrow.
      await srs.reviewWord('w-1', ReviewGrade.known.sm2);
      final due = srs.getDueWords(DateTime.now());
      expect(due, isEmpty);
    });

    test('getDueWords filters by the word type (expressions excluded)', () {
      srs.registerWord('w-1');
      srs.registerExpression('e-1');
      final dueWords = srs.getDueWords(DateTime.now());
      expect(dueWords.map((w) => w.wordId), ['w-1']);
      final dueExpressions = srs.getDueExpressions(DateTime.now());
      expect(dueExpressions.map((w) => w.wordId), ['e-1']);
    });

    test('getDueWords is sorted by dueAt ascending', () async {
      srs.registerWord('w-1');
      srs.registerWord('w-2');
      final due = srs.getDueWords(DateTime.now());
      expect(due, hasLength(2));
      // Fresh words both due ~now; sort must be non-decreasing by dueAt.
      expect(due.first.dueAt.compareTo(due.last.dueAt), lessThanOrEqualTo(0));
    });
  });

  group('lapses & mixed review', () {
    test('getLapseWords returns only words that lapsed, sorted by lapses desc',
        () async {
      srs.registerWord('w-1');
      srs.registerWord('w-2');
      await srs.reviewWord('w-1', ReviewGrade.unknown.sm2);
      await srs.reviewWord('w-1', ReviewGrade.unknown.sm2);
      await srs.reviewWord('w-2', ReviewGrade.unknown.sm2);
      final lapses = srs.getLapseWords();
      expect(lapses.map((w) => w.wordId).toList(), ['w-1', 'w-2']);
      expect(lapses.first.lapses, greaterThan(lapses.last.lapses));
    });

    test('getMixedWords only returns words reviewed at least once', () async {
      srs.registerWord('w-seen');
      srs.registerWord('w-unseen');
      await srs.reviewWord('w-seen', ReviewGrade.known.sm2);
      final mixed = srs.getMixedWords(10);
      expect(mixed.map((w) => w.wordId), ['w-seen']);
    });

    test('getMixedExpressions excludes words and unseen expressions', () async {
      srs.registerWord('w-1');
      srs.registerExpression('e-unseen');
      srs.registerExpression('e-seen');
      await srs.reviewExpression('e-seen', ReviewGrade.known.sm2);
      final mixed = srs.getMixedExpressions(10);
      expect(mixed.map((w) => w.wordId), ['e-seen']);
    });
  });

  group('persistence', () {
    test('state survives a new SrsProvider reading the same DB', () async {
      srs.registerWord('w-1');
      await srs.reviewWord('w-1', ReviewGrade.known.sm2);
      final before = srs.state['w-1']!;

      // A new instance backed by the same DAO/DB should reload the state.
      final reloaded = SrsProvider(prefs, LessonLinkStore(prefs), dao);
      await reloaded.ensureLoaded();
      final after = reloaded.state['w-1']!;
      expect(after.reps, before.reps);
      expect(after.intervalDays, before.intervalDays);
    });

    test('a corrupted srsState JSON degrades to an empty map, not a crash',
        () async {
      await prefs.preferences.setString(LocalStateKeys.srsState, 'not-json');
      final corrupted =
          SrsProvider(prefs, LessonLinkStore(prefs), emptySrsStateDao());
      await corrupted.ensureLoaded();
      expect(corrupted.state, isEmpty);
    });
  });

  group('due count caching', () {
    test('dueCount caches the computed value', () {
      srs.registerWord('w-1');
      srs.registerWord('w-2');

      final first = srs.dueCount;
      expect(first, 2);

      // Call again without any state change; the cached value must be identical.
      final second = srs.dueCount;
      expect(second, first);
    });

    test('dueCount cache is invalidated after a review', () async {
      srs.registerWord('w-1');
      expect(srs.dueCount, 1);

      await srs.reviewWord('w-1', ReviewGrade.known.sm2);
      // After a successful review the word is scheduled for tomorrow, so the
      // due count should drop to 0 and the cache must have been cleared.
      expect(srs.dueCount, 0);
    });

    test('expressionDueCount reflects due expressions', () {
      srs.registerExpression('e-1');
      srs.registerExpression('e-2');

      expect(srs.expressionDueCount, 2);
      expect(srs.getDueExpressions(DateTime.now()), hasLength(2));
    });

    test('expressionDueCount caches the computed value', () {
      srs.registerExpression('e-1');
      srs.registerExpression('e-2');

      final first = srs.expressionDueCount;
      expect(first, 2);
      final second = srs.expressionDueCount;
      expect(second, first);
    });

    test('expressionDueCount cache is invalidated after a review', () async {
      srs.registerExpression('e-1');
      expect(srs.expressionDueCount, 1);

      await srs.reviewExpression('e-1', ReviewGrade.known.sm2);
      expect(srs.expressionDueCount, 0);
    });
  });

  group('review progression', () {
    test('interval follows SM-2 after good/good reviews', () async {
      srs.registerWord('w-1');
      final first = await srs.reviewWord('w-1', ReviewGrade.known.sm2);
      expect(first!.reps, 1);
      expect(first.intervalDays, 1);

      final second = await srs.reviewWord('w-1', ReviewGrade.known.sm2);
      expect(second!.reps, 2);
      expect(second.intervalDays, 4);
    });

    test('a lapse keeps reps and re-schedules for same-day relearn', () async {
      srs.registerWord('w-1');
      await srs.reviewWord('w-1', ReviewGrade.known.sm2);
      await srs.reviewWord('w-1', ReviewGrade.known.sm2);
      final lapsed = await srs.reviewWord('w-1', ReviewGrade.unknown.sm2);

      // reps counts total successes and is preserved across lapses.
      expect(lapsed!.reps, 2);
      expect(lapsed.intervalDays, 1);
      expect(lapsed.lapses, 1);
      expect(lapsed.dueAt.isAfter(DateTime.now()), isTrue);
      // The word reappears in ~10 minutes (same-day relearn).
      final diff = lapsed.dueAt.difference(DateTime.now());
      expect(diff.inMinutes, lessThanOrEqualTo(Sm2Engine.relearnDelayMinutes));
    });
  });

  group('undo gate', () {
    test('undoReview is refused while a grade is in flight, succeeds after',
        () async {
      final completer = Completer<int>();
      srs.setReviewHistoryDaoForTesting(
          _ControllableReviewHistoryDao(completer.future));
      srs.registerWord('w-gate');
      final previous = srs.state['w-gate']!;

      // quality 0 (<3) takes the fail path, which awaits countFailsOnLocalDay
      // (the controllable future) - so the grade stays in flight.
      final gradeFuture = srs.reviewWord('w-gate', 0);
      // Undo must be refused while the grade is mid-flight, so the grade can't
      // overwrite the restored state when it resumes. The caller leaves the
      // undo entry in place and retries once the grade completes.
      expect(await srs.undoWordReview('w-gate', previous), isFalse);

      // Let the grade finish, clearing the in-flight gate.
      completer.complete(0);
      await gradeFuture;

      // After the grade completes, undo is allowed and restores the state.
      expect(await srs.undoWordReview('w-gate', previous), isTrue);
      expect(srs.state['w-gate'], previous);
    });
  });
}
