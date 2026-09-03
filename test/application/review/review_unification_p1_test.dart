import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki_official/engine/official_anki_course_grades_bridge.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P1-A: SRS Queue & Due counts', () {
    late SrsProvider srsProvider;
    late AppPrefs appPrefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      appPrefs = AppPrefs(sp);
      await appPrefs.preferences.setString(LocalStateKeys.srsState, '{}');
      final linkStore = LessonLinkStore(appPrefs);
      final srsDao = emptySrsStateDao();
      srsProvider = SrsProvider(appPrefs, linkStore, srsDao);
    });

    test('getDueWords excludes legacy and official Anki cards', () {
      // Register standard course words
      srsProvider.registerWord('vocab-1');
      srsProvider.registerWord('vocab-2');
      // Register legacy anki cards
      srsProvider.registerWord('anki-import1-c100');
      srsProvider.registerWord('anki-import2-c200');
      // Register official anki projection cards
      srsProvider.registerWord('official-anki-src1-c300');

      final checkTime = DateTime.now().add(const Duration(seconds: 10));

      // Due words for General SRS must ONLY return the 2 course vocab words
      final dueWords = srsProvider.getDueWords(checkTime);
      expect(
          dueWords.map((w) => w.wordId), containsAll(['vocab-1', 'vocab-2']));
      expect(dueWords.any((w) => w.wordId.startsWith('anki-')), isFalse);
      expect(
          dueWords.any((w) => w.wordId.startsWith('official-anki-')), isFalse);
      expect(dueWords.length, 2);

      // dueCount & dueWordIdSet must also exclude Anki
      expect(srsProvider.dueCount, 2);
      expect(srsProvider.dueWordIdSet, {'vocab-1', 'vocab-2'});

      // getDueAnkiWords must return Anki items
      final ankiDue = srsProvider.getDueAnkiWords(checkTime);
      expect(ankiDue.length, 3);
      expect(
        ankiDue.map((w) => w.wordId),
        containsAll([
          'anki-import1-c100',
          'anki-import2-c200',
          'official-anki-src1-c300',
        ]),
      );
    });
  });

  group('P1-B: Official Bridge Callback Safety', () {
    const fullFlags = OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
      renderer: true,
      scheduler: true,
      courseGradesScheduler: true,
    );

    test(
        'answerOfficialCard returns false when no onAnswer callback is injected',
        () async {
      const bridge = OfficialAnkiCourseGradesBridgeImpl(
        flags: fullFlags,
        onAnswer: null,
      );

      final result = await bridge.answerOfficialCard(
        wordId: 'official-anki-src1-c123',
        rating: 'good',
      );

      expect(result, isFalse,
          reason: 'Must not return fake success when unhandled');
    });

    test('answerOfficialCard forwards to callback when injected', () async {
      var calledCardId = 0;
      var calledRating = '';
      final bridge = OfficialAnkiCourseGradesBridgeImpl(
        flags: fullFlags,
        onAnswer: (cardId, rating, ms) async {
          calledCardId = cardId;
          calledRating = rating;
          return true;
        },
      );

      final result = await bridge.answerOfficialCard(
        wordId: 'official-anki-src1-c999',
        rating: 'again',
      );

      expect(result, isTrue);
      expect(calledCardId, 999);
      expect(calledRating, 'again');
    });
  });
}
