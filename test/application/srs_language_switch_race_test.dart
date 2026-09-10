// Regression tests for language-switch races in [SrsQueueProvider] (the
// multi-language coexistence architecture):
//
// - a review grade suspended on its fail-count await must persist under the
//   language it was graded in, not the language active when it resumes, and
//   must not clobber the new language's freshly-hydrated cache;
// - the same invariant for undo;
// - two rapid switches must not leave a mixed-language cache behind (the
//   hydration generation guard);
// - clear() resets only the current language's queue;
// - setLanguageFilter bumps the review-data revision exactly once per switch.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/review_dashboard/review_data_revision.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

/// A [ReviewHistoryDao] whose fail-count query and latest-event delete can be
/// parked on controllable futures, and which records every inserted event so
/// tests can assert the language tag persisted alongside the race.
class _GatedReviewHistoryDao implements ReviewHistoryDao {
  _GatedReviewHistoryDao({
    Future<int>? failCountFuture,
    Future<void>? deleteGate,
  })  : _failCountFuture = failCountFuture ?? Future<int>.value(0),
        _deleteGate = deleteGate ?? Future<void>.value();

  final Future<int> _failCountFuture;
  final Future<void> _deleteGate;
  final List<ReviewEventRecord> events = [];

  @override
  Future<int> countFailsOnLocalDay(
    String cardId,
    DateTime day, {
    String? languageCode,
  }) =>
      _failCountFuture;

  @override
  Future<void> insertEvent(ReviewEventRecord event) async {
    events.add(event);
  }

  @override
  Future<bool> deleteLatestForCard(String cardId, {String? languageCode}) async {
    await _deleteGate;
    return true;
  }

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
    // Same reset rationale as srs_provider_test.dart: mock values don't clear
    // an already-cached StreamingSharedPreferences instance.
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.preferences.setString(LocalStateKeys.srsState, '{}');
    // Skip the legacy prefs->SQLite migration path; these tests seed the DB
    // directly.
    await prefs.preferences.setBool('srs.migratedToSqlite.srs', true);
    linkStore = LessonLinkStore(prefs);
    dao = emptySrsStateDao();
    srs = SrsProvider(prefs, linkStore, dao);
    srs.setSchedulerForTesting(const Sm2Engine());
  });

  group('review racing a language switch', () {
    test('grade persists under the graded language and spares the new cache',
        () async {
      final failCount = Completer<int>();
      final reviewDao = _GatedReviewHistoryDao(failCountFuture: failCount.future);
      srs.setReviewHistoryDaoForTesting(reviewDao);
      srs.registerWord('w-1');
      expect(srs.languageFilter, LanguageCodes.turkish);

      // quality 0 (<3) parks the grade on the fail-count await.
      final gradeFuture = srs.reviewWord('w-1', 0);
      // Switch language while the grade is suspended.
      await srs.setLanguageFilter(LanguageCodes.french);
      failCount.complete(1);
      await gradeFuture;

      // The DB write is tagged with the language the card belongs to…
      expect(
        (await dao.loadQueue('srs', languageCode: LanguageCodes.turkish)).keys,
        ['w-1'],
      );
      // …not the language that happened to be active when it resumed.
      expect(
        await dao.loadQueue('srs', languageCode: LanguageCodes.french),
        isEmpty,
      );
      expect(reviewDao.events, hasLength(1));
      expect(reviewDao.events.single.languageCode, LanguageCodes.turkish);

      // The freshly-hydrated French cache was not clobbered by the Turkish
      // map the resumed grade still held.
      expect(srs.state, isEmpty);
      expect(srs.languageFilter, LanguageCodes.french);
    });
  });

  group('undo racing a language switch', () {
    test('undo restores the graded language row and spares the new cache',
        () async {
      final deleteGate = Completer<void>();
      final reviewDao = _GatedReviewHistoryDao(deleteGate: deleteGate.future);
      srs.setReviewHistoryDaoForTesting(reviewDao);
      srs.registerWord('w-1');
      final previous = srs.state['w-1']!;

      final undoFuture = srs.undoWordReview('w-1', previous);
      await srs.setLanguageFilter(LanguageCodes.french);
      deleteGate.complete();
      expect(await undoFuture, isTrue);

      expect(
        (await dao.loadQueue('srs', languageCode: LanguageCodes.turkish)).keys,
        ['w-1'],
      );
      expect(
        await dao.loadQueue('srs', languageCode: LanguageCodes.french),
        isEmpty,
      );
      expect(srs.state, isEmpty);
    });
  });

  group('rapid double switch', () {
    test('a slow load for the abandoned language must not mix into the cache',
        () async {
      await dao.upsert(
        'srs',
        SrsWord.fresh('w-1'),
        languageCode: LanguageCodes.turkish,
      );
      await dao.upsert(
        'srs',
        SrsWord.fresh('fr-w-bonjour'),
        languageCode: LanguageCodes.french,
      );

      // Fire both switches without awaiting in between. The French load is
      // issued first and resolves first; without the generation guard its
      // result would merge via putIfAbsent and survive as a mixed cache.
      final toFrench = srs.setLanguageFilter(LanguageCodes.french);
      final backToTurkish = srs.setLanguageFilter(LanguageCodes.turkish);
      await backToTurkish;
      await toFrench;

      expect(srs.languageFilter, LanguageCodes.turkish);
      expect(srs.state.keys, {'w-1'});
    });
  });

  group('clear is language-scoped', () {
    test('clearing the current language spares the other language rows',
        () async {
      await dao.upsert(
        'srs',
        SrsWord.fresh('w-1'),
        languageCode: LanguageCodes.turkish,
      );
      await dao.upsert(
        'srs',
        SrsWord.fresh('fr-w-bonjour'),
        languageCode: LanguageCodes.french,
      );
      await srs.setLanguageFilter(LanguageCodes.french);

      await srs.clear();

      expect(srs.state, isEmpty);
      expect(
        await dao.loadQueue('srs', languageCode: LanguageCodes.french),
        isEmpty,
      );
      expect(
        (await dao.loadQueue('srs', languageCode: LanguageCodes.turkish)).keys,
        ['w-1'],
      );
    });
  });

  group('review-data revision', () {
    test('setLanguageFilter bumps the revision exactly once', () async {
      final revision = ReviewDataRevision();
      GetIt.I.registerSingleton<ReviewDataRevision>(revision);
      addTearDown(GetIt.I.reset);

      await srs.setLanguageFilter(LanguageCodes.french);

      expect(revision.value, 1);
    });
  });
}
