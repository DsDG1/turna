// Tests for [GrammarReviewProvider]: register/review/due round-trip,
// persistence across instances, and isolation from the word-SRS queue
// ([SrsProvider]).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/core/sm2.dart';
import 'package:varnamala/data/srs_state_dao.dart';
import 'package:varnamala/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

AppPrefs _newPrefs(StreamingSharedPreferences p) => AppPrefs(p);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences prefs;
  late AppPrefs appPrefs;
  late SrsStateDao dao;

  setUp(() async {
    // Back StreamingSharedPreferences with the in-memory SharedPreferences
    // mock so reads/writes resolve without a platform plugin.
    SharedPreferences.setMockInitialValues({});
    prefs = await StreamingSharedPreferences.instance;
    await prefs.remove(LocalStateKeys.grammarReviewState);
    await prefs.remove(LocalStateKeys.srsState);
    await prefs.remove(LocalStateKeys.lessonWordLinks);
    appPrefs = _newPrefs(prefs);
    dao = emptySrsStateDao();
  });

  group('GrammarReviewProvider', () {
    test('register makes a grammar point due immediately', () {
      final grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs), dao);
      expect(grammar.dueCount, 0);
      grammar.registerGrammarPoint('gp.present-a');
      expect(grammar.dueCount, 1);
      expect(grammar.getDueGrammarPoints().single.wordId, 'gp.present-a');
    });

    test('registerAll is idempotent', () {
      final grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs), dao);
      grammar.registerAll(['gp.a', 'gp.b', 'gp.a']);
      expect(grammar.dueCount, 2);
      grammar.registerAll(['gp.a', 'gp.b']); // no-op
      expect(grammar.dueCount, 2);
    });

    test('review with Good reschedules the point into the future', () async {
      final grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs), dao);
      grammar.registerGrammarPoint('gp.a');
      expect(grammar.dueCount, 1);

      final updated =
          await grammar.reviewWithQuality('gp.a', ReviewGrade.known);
      expect(updated, isNotNull);
      expect(updated!.reps, 1);
      // Reviewed just now with Good -> next due is in the future.
      expect(updated.dueAt.isAfter(DateTime.now()), isTrue);
      expect(grammar.dueCount, 0);
    });

    test('review on an unknown id returns null', () async {
      final grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs), dao);
      expect(await grammar.reviewWithQuality('nope', ReviewGrade.known),
          isNull);
    });

    test('state persists across provider instances', () async {
      final first = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs), dao);
      first.registerGrammarPoint('gp.a');
      await first.reviewWithQuality('gp.a', ReviewGrade.known);

      // A new provider reading the same DB must restore the state.
      final second = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs), dao);
      await second.ensureLoaded();
      expect(second.totalRegistered, 1);
      expect(second.totalSeen, 1); // reps >= 1 after one review
      expect(second.dueCount, 0);
    });

    test('markDueNow registers unseen points and re-dues seen ones', () async {
      final grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs), dao);

      await grammar.markDueNow('gp.a');
      expect(grammar.dueCount, 1);
      expect(grammar.state['gp.a']!.dueAt.isAfter(DateTime.now().subtract(
            const Duration(seconds: 2),
          )),
          isTrue);

      // Schedule into the future via Good, then pull back with markDueNow.
      await grammar.reviewWithQuality('gp.a', ReviewGrade.known);
      expect(grammar.dueCount, 0);

      await grammar.markDueNow('gp.a');
      expect(grammar.dueCount, 1);
      // SM-2 history (reps) is preserved; only dueAt is forced now.
      expect(grammar.state['gp.a']!.reps, 1);
    });

    test('is isolated from the word SRS queue', () async {
      final grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs), dao);
      final srs = SrsProvider(appPrefs, LessonLinkStore(appPrefs), dao);

      grammar.registerGrammarPoint('gp.a');
      expect(grammar.dueCount, 1);
      // The grammar queue must not leak into the word queue.
      expect(srs.dueCount, 0);
      expect(srs.state.containsKey('gp.a'), isFalse);

      // And writing to the word queue must not leak into grammar.
      srs.registerWord('w.apple');
      expect(srs.dueCount, 1);
      expect(grammar.dueCount, 1); // unchanged — only gp.a
      expect(grammar.state.containsKey('w.apple'), isFalse);

      // DB-level queue isolation (queueId scoping) is covered by
      // srs_state_dao_test.dart; here the in-memory caches above already
      // prove the two queues don't leak into each other.
    });

    test('recordLessonLinks records the grammar link type', () async {
      final grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs), dao);
      grammar.registerGrammarPoint('gp.a');
      await grammar.recordLessonLinks(
        ids: ['gp.a'],
        lessonId: 'l-intro',
        lessonName: 'Intro',
      );
      expect(grammar.getLessonNameForGrammarPoint('gp.a'), 'Intro');
    });
  });
}