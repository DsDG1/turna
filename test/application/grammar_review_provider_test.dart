// Tests for [GrammarReviewProvider]: register/review/due round-trip,
// persistence across instances, and isolation from the word-SRS queue
// ([SrsProvider]).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/core/sm2.dart';
import 'package:varnamala/service/locator.dart';

AppPrefs _newPrefs(StreamingSharedPreferences p) => AppPrefs(p);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences prefs;
  late AppPrefs appPrefs;

  setUp(() async {
    // Back StreamingSharedPreferences with the in-memory SharedPreferences
    // mock so reads/writes resolve without a platform plugin.
    SharedPreferences.setMockInitialValues({});
    prefs = await StreamingSharedPreferences.instance;
    await prefs.remove(LocalStateKeys.grammarReviewState);
    await prefs.remove(LocalStateKeys.srsState);
    await prefs.remove(LocalStateKeys.lessonWordLinks);
    appPrefs = _newPrefs(prefs);
  });

  group('GrammarReviewProvider', () {
    test('register makes a grammar point due immediately', () {
      final grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs));
      expect(grammar.dueCount, 0);
      grammar.registerGrammarPoint('gp.present-a');
      expect(grammar.dueCount, 1);
      expect(grammar.getDueGrammarPoints().single.wordId, 'gp.present-a');
    });

    test('registerAll is idempotent', () {
      final grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs));
      grammar.registerAll(['gp.a', 'gp.b', 'gp.a']);
      expect(grammar.dueCount, 2);
      grammar.registerAll(['gp.a', 'gp.b']); // no-op
      expect(grammar.dueCount, 2);
    });

    test('review with Good reschedules the point into the future', () async {
      final grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs));
      grammar.registerGrammarPoint('gp.a');
      expect(grammar.dueCount, 1);

      final updated =
          await grammar.reviewWithQuality('gp.a', ReviewQuality.good);
      expect(updated, isNotNull);
      expect(updated!.reps, 1);
      // Reviewed just now with Good -> next due is in the future.
      expect(updated.dueAt.isAfter(DateTime.now()), isTrue);
      expect(grammar.dueCount, 0);
    });

    test('review on an unknown id returns null', () async {
      final grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs));
      expect(await grammar.reviewWithQuality('nope', ReviewQuality.good),
          isNull);
    });

    test('state persists across provider instances', () async {
      final first = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs));
      first.registerGrammarPoint('gp.a');
      await first.reviewWithQuality('gp.a', ReviewQuality.good);

      // A new provider reading the same prefs must restore the state.
      final second = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs));
      expect(second.totalRegistered, 1);
      expect(second.totalSeen, 1); // reps >= 1 after one review
      expect(second.dueCount, 0);
    });

    test('markDueNow registers unseen points and re-dues seen ones', () async {
      final grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs));

      await grammar.markDueNow('gp.a');
      expect(grammar.dueCount, 1);
      expect(grammar.state['gp.a']!.dueAt.isAfter(DateTime.now().subtract(
            const Duration(seconds: 2),
          )),
          isTrue);

      // Schedule into the future via Good, then pull back with markDueNow.
      await grammar.reviewWithQuality('gp.a', ReviewQuality.good);
      expect(grammar.dueCount, 0);

      await grammar.markDueNow('gp.a');
      expect(grammar.dueCount, 1);
      // SM-2 history (reps) is preserved; only dueAt is forced now.
      expect(grammar.state['gp.a']!.reps, 1);
    });

    test('is isolated from the word SRS queue', () async {
      final grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs));
      final srs = SrsProvider(appPrefs, LessonLinkStore(appPrefs));

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

      // The persisted keys are distinct.
      final grammarRaw = prefs
          .getString(LocalStateKeys.grammarReviewState, defaultValue: '{}');
      final srsRaw =
          prefs.getString(LocalStateKeys.srsState, defaultValue: '{}');
      expect((jsonDecode(grammarRaw.getValue()) as Map).containsKey('gp.a'),
          isTrue);
      expect((jsonDecode(srsRaw.getValue()) as Map).containsKey('w.apple'),
          isTrue);
      expect((jsonDecode(grammarRaw.getValue()) as Map).containsKey('w.apple'),
          isFalse);
      expect((jsonDecode(srsRaw.getValue()) as Map).containsKey('gp.a'),
          isFalse);
    });

    test('recordLessonLinks records the grammar link type', () async {
      final grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs));
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