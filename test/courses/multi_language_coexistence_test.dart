// 双语言并存验收测试。法语课程（assets/courses/french/）是多语言并存
// 机制的验收 fixture，不是真的课程，不在开发计划内——它在这里只充当
// "第二门内置语言"，用来逼出目录并排、队列隔离、卸载级联等跨语言行为。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/course_catalog.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/review_dashboard/insights_repository.dart';
import 'package:turna/application/review_dashboard/review_data_revision.dart';
import 'package:turna/application/review_progress_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_database_seeder.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/data/mistake_repository.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/domain/study/study_log.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/data/study_log_repository.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;

  setUp(() async {
    LanguageContentStore.resetForTest();
    CourseLoader.clearDatabaseOverride();
    db = await seedInMemoryCourseDb();
  });

  tearDown(() async {
    LanguageContentStore.resetForTest();
    CourseLoader.clearDatabaseOverride();
    await db.close();
  });

  test('seeder installs turkish and french into one database', () async {
    final repo = CourseRepository(db);
    final tr = await repo.sectionShells(languageCode: LanguageCodes.turkish);
    final fr = await repo.sectionShells(languageCode: LanguageCodes.french);
    expect(tr, isNotEmpty);
    expect(fr, isNotEmpty);
    expect(tr.map((s) => s.id).toSet().intersection(fr.map((s) => s.id).toSet()),
        isEmpty);

    final trVocab = await repo.vocabulary(languageCode: LanguageCodes.turkish);
    final frVocab = await repo.vocabulary(languageCode: LanguageCodes.french);
    expect(trVocab.any((w) => w.id == 'w-merhaba'), isTrue);
    expect(frVocab.any((w) => w.id == 'fr-w-bonjour'), isTrue);
    expect(trVocab.any((w) => w.id == 'fr-w-bonjour'), isFalse);
  });

  test('catalog lists each builtin language and scope isolates sections',
      () async {
    final provider = CourseProvider();
    await provider.load();

    final builtins = provider.catalogEntries.where((e) => e.isBuiltin).toList();
    expect(builtins.map((e) => e.displayName), containsAll(['Turkish', 'French']));

    await provider.setScope(const BuiltinCourseScope(LanguageCodes.turkish));
    expect(
      provider.sections.every((s) => s.id.startsWith('fr-') == false),
      isTrue,
    );
    expect(provider.sections, isNotEmpty);

    await provider.setScope(const BuiltinCourseScope(LanguageCodes.french));
    expect(provider.sections.every((s) => s.id.startsWith('fr-')), isTrue);
    expect(provider.sections, isNotEmpty);
  });

  test('SRS due queues, review history and mistakes do not leak across languages',
      () async {
    final srs = SrsStateDao(db);
    final history = ReviewHistoryDao(db);
    final now = DateTime(2026, 9, 8, 10);

    await srs.upsert(
      'srs',
      SrsWord(
        wordId: 'w-merhaba',
        dueAt: now.subtract(const Duration(hours: 1)),
        reps: 3,
        intervalDays: 4,
      ),
      languageCode: LanguageCodes.turkish,
    );
    await srs.upsert(
      'srs',
      SrsWord(
        wordId: 'fr-w-bonjour',
        dueAt: now.subtract(const Duration(hours: 1)),
        reps: 2,
        intervalDays: 1,
      ),
      languageCode: LanguageCodes.french,
    );

    final trQueue = await srs.loadQueue('srs', languageCode: LanguageCodes.turkish);
    final frQueue = await srs.loadQueue('srs', languageCode: LanguageCodes.french);
    expect(trQueue.keys, ['w-merhaba']);
    expect(frQueue.keys, ['fr-w-bonjour']);

    await srs.upsert(
      'grammar',
      SrsWord(
        wordId: 'g-present-to-be',
        dueAt: now.subtract(const Duration(hours: 1)),
        reps: 1,
      ),
      languageCode: LanguageCodes.turkish,
    );
    await srs.upsert(
      'grammar',
      SrsWord(
        wordId: 'fr-g-etre',
        dueAt: now.subtract(const Duration(hours: 1)),
        reps: 1,
      ),
      languageCode: LanguageCodes.french,
    );
    expect(
      (await srs.loadQueue('grammar', languageCode: LanguageCodes.turkish)).keys,
      ['g-present-to-be'],
    );
    expect(
      (await srs.loadQueue('grammar', languageCode: LanguageCodes.french)).keys,
      ['fr-g-etre'],
    );

    await history.insertEvent(ReviewEventRecord(
      cardId: 'w-merhaba',
      queue: 'srs',
      reviewedAt: now,
      quality: 4,
      prevIntervalDays: 1,
      nextIntervalDays: 4,
      prevEase: 2.5,
      nextEase: 2.6,
      reps: 3,
      lapses: 0,
      languageCode: LanguageCodes.turkish,
    ));
    await history.insertEvent(ReviewEventRecord(
      cardId: 'fr-w-bonjour',
      queue: 'srs',
      reviewedAt: now,
      quality: 5,
      prevIntervalDays: 1,
      nextIntervalDays: 1,
      prevEase: 2.5,
      nextEase: 2.6,
      reps: 2,
      lapses: 0,
      languageCode: LanguageCodes.french,
    ));
    final from = now.subtract(const Duration(hours: 1));
    final to = now.add(const Duration(hours: 1));
    expect(
      (await history.eventsBetween(
        from,
        to,
        languageCode: LanguageCodes.turkish,
      ))
          .map((e) => e.cardId),
      ['w-merhaba'],
    );
    expect(
      (await history.eventsBetween(
        from,
        to,
        languageCode: LanguageCodes.french,
      ))
          .map((e) => e.cardId),
      ['fr-w-bonjour'],
    );
    expect(
      (await history.recentEvents(languageCode: LanguageCodes.turkish))
          .map((e) => e.cardId),
      ['w-merhaba'],
    );
    final trDays = await history.dailyActivityBetween(
      DateTime(now.year, now.month, now.day),
      DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
      languageCode: LanguageCodes.turkish,
    );
    final frDays = await history.dailyActivityBetween(
      DateTime(now.year, now.month, now.day),
      DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
      languageCode: LanguageCodes.french,
    );
    expect(trDays.single.reviewedCount, 1);
    expect(frDays.single.reviewedCount, 1);

    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    final prefs = AppPrefs(sp);
    final mistakes = MistakeProvider(prefs)
      ..useRepository(MistakeRepository(db));
    await mistakes.setLanguage(LanguageCodes.turkish);
    await mistakes.record(MistakeEntry(
      id: 'm-tr',
      lessonId: 's1-l1',
      stageId: 'st',
      interactionId: 'i1',
      wordId: 'w-merhaba',
      timestamp: now,
      interactionSnapshot: Interaction.multipleChoice(
        id: 'i1',
        prompt: 'tr',
        options: const ['a', 'b', 'c', 'd'],
        correctIndex: 0,
      ),
    ));
    await mistakes.setLanguage(LanguageCodes.french);
    expect(mistakes.entries, isEmpty);
    await mistakes.record(MistakeEntry(
      id: 'm-fr',
      lessonId: 'fr-s1-l1',
      stageId: 'st',
      interactionId: 'i2',
      wordId: 'fr-w-bonjour',
      timestamp: now,
      interactionSnapshot: Interaction.multipleChoice(
        id: 'i2',
        prompt: 'fr',
        options: const ['a', 'b', 'c', 'd'],
        correctIndex: 0,
      ),
    ));
    expect(mistakes.entries.map((e) => e.id), ['m-fr']);
    await mistakes.setLanguage(LanguageCodes.turkish);
    expect(mistakes.entries.map((e) => e.id), ['m-tr']);

    final logs = StudyLogRepository(prefs);
    final study = StudyStatsProvider(logs, mistakes);
    study.setLanguage(LanguageCodes.turkish);
    await study.recordActivity(
      type: StudyActivityType.srsReview,
      xpEarned: 10,
      durationSeconds: 60,
      correctCount: 1,
      wordIds: const ['w-merhaba'],
    );
    study.setLanguage(LanguageCodes.french);
    await study.recordActivity(
      type: StudyActivityType.srsReview,
      xpEarned: 50,
      durationSeconds: 120,
      correctCount: 1,
      wordIds: const ['fr-w-bonjour'],
    );
    study.setLanguage(LanguageCodes.turkish);
    expect(await study.getTotalRecordedXp(), 10);
    expect(await study.getTotalRecordedReviews(), 1);
    expect((await study.getTodayStats()).totalXp, 10);
    study.setLanguage(LanguageCodes.french);
    expect(await study.getTotalRecordedXp(), 50);
    expect(await study.getTotalRecordedReviews(), 1);
    expect((await study.getTodayStats()).totalXp, 50);
  });

  test('insights heatmap and retention do not mix languages', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    final prefs = AppPrefs(sp);
    final link = LessonLinkStore(prefs);
    final history = ReviewHistoryDao(db);
    final srsDao = SrsStateDao(db);
    final now = DateTime(2026, 9, 8, 12);

    Future<void> putEvent(String cardId, String language, int quality) {
      return history.insertEvent(ReviewEventRecord(
        cardId: cardId,
        queue: 'srs',
        reviewedAt: now,
        quality: quality,
        prevIntervalDays: 1,
        nextIntervalDays: 4,
        prevEase: 2.5,
        nextEase: 2.6,
        reps: 3,
        lapses: 0,
        languageCode: language,
      ));
    }

    await putEvent('w-merhaba', LanguageCodes.turkish, 4);
    await putEvent('fr-w-bonjour', LanguageCodes.french, 5);
    await putEvent('fr-w-merci', LanguageCodes.french, 3);

    final srs = SrsProvider(prefs, link, srsDao);
    final grammar = GrammarReviewProvider(prefs, link, srsDao);
    await srs.setLanguageFilter(LanguageCodes.turkish);
    await grammar.setLanguageFilter(LanguageCodes.turkish);
    final progress = ReviewProgressProvider(
      history,
      srs,
      grammar,
      AnkiImportDao(db),
    );
    final insights = InsightsRepository(progress, ReviewDataRevision());

    Future<ReviewProgressSnapshot> loadAll() {
      return insights.load(const InsightsQuery(
        range: EventRange.all,
        source: ReviewSource.all,
        type: ProgressTypeFilter.all,
      ));
    }

    int activitySum(ReviewProgressSnapshot snap) =>
        snap.activity.fold<int>(0, (n, row) => n + row.reviewedCount);

    final trSnap = await loadAll();
    expect(trSnap.aggregate.totalReviews, 1);
    expect(activitySum(trSnap), 1);
    expect(
      trSnap.bySource
          .where((row) => row.source.kind == ReviewSourceKind.course)
          .single
          .reviews,
      1,
    );
    final trSources = await progress.listSources();
    expect(trSources.map((s) => s.kind), isNot(contains(ReviewSourceKind.ankiDeck)));

    await srs.setLanguageFilter(LanguageCodes.french);
    await grammar.setLanguageFilter(LanguageCodes.french);
    insights.invalidate();
    final frSnap = await loadAll();
    expect(frSnap.aggregate.totalReviews, 2);
    expect(activitySum(frSnap), 2);
    expect(
      frSnap.bySource
          .where((row) => row.source.kind == ReviewSourceKind.course)
          .single
          .reviews,
      2,
    );
  });

  test('uninstalling french leaves turkish tree and progress', () async {
    final srs = SrsStateDao(db);
    final now = DateTime(2026, 9, 8);
    await srs.upsert(
      'srs',
      SrsWord(wordId: 'w-merhaba', dueAt: now, reps: 4, intervalDays: 7),
      languageCode: LanguageCodes.turkish,
    );
    await srs.upsert(
      'srs',
      SrsWord(wordId: 'fr-w-bonjour', dueAt: now, reps: 1, intervalDays: 1),
      languageCode: LanguageCodes.french,
    );

    final provider = CourseProvider();
    await provider.load();
    await provider.uninstallBuiltinLanguage(LanguageCodes.french);

    final repo = CourseRepository(db);
    expect(await repo.sectionShells(languageCode: LanguageCodes.french), isEmpty);
    expect(await repo.vocabulary(languageCode: LanguageCodes.french), isEmpty);
    expect(
      await repo.sectionShells(languageCode: LanguageCodes.turkish),
      isNotEmpty,
    );
    expect(
      (await srs.loadQueue('srs', languageCode: LanguageCodes.turkish)).keys,
      ['w-merhaba'],
    );
    expect(
      await srs.loadQueue('srs', languageCode: LanguageCodes.french),
      isEmpty,
    );

    final catalog = await CourseCatalog.load();
    expect(
      catalog.where((e) => e.isBuiltin).map((e) => (e.scope as BuiltinCourseScope).canonicalLanguageCode),
      isNot(contains(LanguageCodes.french)),
    );
    expect(
      catalog.where((e) => e.isBuiltin).map((e) => (e.scope as BuiltinCourseScope).canonicalLanguageCode),
      contains(LanguageCodes.turkish),
    );
  });

  test('uninstalled language survives restart seeding and can be restored',
      () async {
    final provider = CourseProvider();
    await provider.load();
    await provider.uninstallBuiltinLanguage(LanguageCodes.french);

    // The marker must stop cold-start seeding from resurrecting french.
    final reseeded = await DatabaseSeeder(db).seedIfNeeded();
    expect(reseeded, isFalse);
    final repo = CourseRepository(db);
    expect(await repo.sectionShells(languageCode: LanguageCodes.french), isEmpty);
    expect(await repo.uninstalledLanguageCodes(), {LanguageCodes.french});

    // Restorable list surfaces the marker; catalog keeps counting cards.
    expect(
      provider.restorableBuiltinLanguages.map((l) => l.code),
      [LanguageCodes.french],
    );
    final entries = provider.catalogEntries;
    final trEntry = entries.firstWhere(
      (e) => e.isBuiltin && (e.scope as BuiltinCourseScope).languageCode == LanguageCodes.turkish,
    );
    expect(trEntry.cardCount, greaterThan(0));

    // Restore: marker cleared, content reseeded, list drained.
    await provider.reinstallBuiltinLanguage(LanguageCodes.french);
    expect(
      await repo.sectionShells(languageCode: LanguageCodes.french),
      isNotEmpty,
    );
    expect(await repo.vocabulary(languageCode: LanguageCodes.french), isNotEmpty);
    expect(await repo.uninstalledLanguageCodes(), isEmpty);
    expect(provider.restorableBuiltinLanguages, isEmpty);
    // A later cold start must not re-trigger seeding either.
    expect(await DatabaseSeeder(db).seedIfNeeded(), isFalse);
  });

  test('recentReviews stays within the requested language', () async {
    final srs = SrsStateDao(db);
    final now = DateTime(2026, 9, 8);
    await srs.upsert(
      'srs',
      SrsWord(
        wordId: 'w-merhaba',
        dueAt: now,
        reps: 3,
        lastReviewedAt: now,
      ),
      languageCode: LanguageCodes.turkish,
    );
    await srs.upsert(
      'srs',
      SrsWord(
        wordId: 'fr-w-bonjour',
        dueAt: now,
        reps: 1,
        lastReviewedAt: now,
      ),
      languageCode: LanguageCodes.french,
    );

    final frOnly = await srs.recentReviews(
      languageCode: LanguageCodes.french,
    );
    expect(frOnly.map((w) => w.wordId), everyElement(startsWith('fr-')));
    expect(frOnly.map((w) => w.wordId), ['fr-w-bonjour']);

    final all = await srs.recentReviews();
    expect(all.length, 2, reason: 'no filter keeps the legacy cross view');
  });

  test('packed registry resolves french TTS locale and display name', () async {
    await LanguageRegistry.instance.load();
    expect(LanguageRegistry.instance.displayName('fr'), 'French');
    expect(LanguageRegistry.instance.ttsLocale('fr'), 'fr-FR');
    expect(LanguageRegistry.instance.ttsLanguageCode('fr'), 'fr');

    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    final language = LanguageProvider(AppPrefs(sp));
    language.setLanguageCode(LanguageCodes.french);
    expect(language.displayName, 'French');
    expect(language.ttsLanguageCode, 'fr');
    expect(language.selectedLanguageCode, LanguageCodes.french);
  });
}
