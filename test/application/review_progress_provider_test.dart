import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/application/review_progress_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/data/anki_import_dao.dart';
import 'package:varnamala/data/review_history_dao.dart';
import 'package:varnamala/domain/course/srs_word.dart';
import 'package:varnamala/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late SrsProvider srs;
  late GrammarReviewProvider grammar;
  late ReviewHistoryDao reviewDao;
  late AnkiImportDao ankiDao;
  late ReviewProgressProvider progress;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    final link = LessonLinkStore(prefs);
    final srsDao = emptySrsStateDao();
    reviewDao = emptyReviewHistoryDao();
    ankiDao = AnkiImportDao(emptyInMemoryCourseDatabase());
    srs = SrsProvider(prefs, link, srsDao);
    grammar = GrammarReviewProvider(prefs, link, emptySrsStateDao());
    progress = ReviewProgressProvider(reviewDao, srs, grammar, ankiDao);
  });

  test('importIdFromWordId parses anki ids', () {
    expect(
      ReviewProgressProvider.importIdFromWordId('anki-abc123-c42'),
      'abc123',
    );
    expect(ReviewProgressProvider.importIdFromWordId('merhaba'), isNull);
  });

  test('snapshot groups course vs anki vs grammar', () async {
    srs.registerWord('merhaba');
    srs.registerWord('anki-deck1-c1');
    srs.registerWord('anki-deck1-c2');
    grammar.registerGrammarPoint('gp-1');

    final snap = await progress.snapshot();
    expect(snap.aggregate.totalCards, 4);
    expect(snap.bySource.length, greaterThanOrEqualTo(2));

    final kinds = snap.bySource.map((r) => r.source.kind).toSet();
    expect(kinds.contains(ReviewSourceKind.course), isTrue);
    expect(kinds.contains(ReviewSourceKind.ankiDeck), isTrue);
    expect(kinds.contains(ReviewSourceKind.grammar), isTrue);

    final anki = snap.bySource
        .firstWhere((r) => r.source.kind == ReviewSourceKind.ankiDeck);
    expect(anki.totalCards, 2);
  });

  test('source filter limits cards', () async {
    srs.registerWord('merhaba');
    srs.registerWord('anki-x-c1');
    grammar.registerGrammarPoint('gp-1');

    final courseOnly = await progress.snapshot(const ReviewProgressFilter(
      source: ReviewSource.course,
    ));
    expect(courseOnly.aggregate.totalCards, 1);

    final grammarOnly = await progress.snapshot(const ReviewProgressFilter(
      source: ReviewSource.grammar,
    ));
    expect(grammarOnly.aggregate.totalCards, 1);
  });

  test('overdue filter excludes future due', () async {
    srs.registerWord('w-now');
    final future = SrsWord(
      wordId: 'w-later',
      dueAt: DateTime.now().add(const Duration(days: 5)),
      reps: 1,
      intervalDays: 5,
      lastReviewedAt: DateTime.now(),
    );
    await srs.bulkImportStates({'w-later': future});

    final overdue = await progress.snapshot(const ReviewProgressFilter(
      due: DueFilter.overdue,
    ));
    // Only w-now is due immediately (fresh).
    expect(overdue.aggregate.totalCards, 1);
    expect(overdue.aggregate.forecast.dueToday, 1);
  });
}
