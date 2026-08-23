import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/review_progress_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/service/locator.dart';

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

  test('snapshot groups explicit course vs anki vs grammar identity', () async {
    srs.registerWord('merhaba');
    srs.registerWord(
      'opaque-1',
      sourceKind: SrsSourceKind.ankiLegacy,
      sourceId: 'deck1',
    );
    srs.registerWord(
      'opaque-2',
      sourceKind: SrsSourceKind.ankiLegacy,
      sourceId: 'deck1',
    );
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
    srs.registerWord(
      'opaque-x',
      sourceKind: SrsSourceKind.ankiLegacy,
      sourceId: 'x',
    );
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

  test('deleted source keeps historical identity but is inactive', () async {
    final now = DateTime.now();
    await reviewDao.insertEvent(ReviewEventRecord(
      cardId: 'opaque-deleted-card',
      queue: 'srs',
      reviewedAt: now,
      quality: 4,
      prevIntervalDays: 1,
      nextIntervalDays: 2,
      prevEase: 2.5,
      nextEase: 2.5,
      reps: 1,
      lapses: 0,
      sourceKind: SrsSourceKind.ankiLegacy,
      sourceId: 'deleted-source',
    ));

    final sources = await progress.listSources();
    final deleted = sources.singleWhere((s) => s.id == 'anki:deleted-source');
    expect(deleted.active, isFalse);
    final snapshot = await progress.snapshot();
    final row = snapshot.bySource
        .singleWhere((source) => source.source.id == 'anki:deleted-source');
    expect(row.totalCards, 0);
    expect(row.reviews, 1);
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
