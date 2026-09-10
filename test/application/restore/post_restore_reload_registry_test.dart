// Regression tests for [PostRestoreReloadRegistry]'s learning-state steps:
// after a backup restore switches the persisted language, the SRS / grammar
// queues must re-point their language filter at the restored selection before
// reloading, and the mistake log must actually reload from SQLite instead of
// staying empty until the next record.

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/restore/post_restore_reload_registry.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/data/mistake_repository.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late SrsStateDao srsDao;
  late MistakeRepository mistakeRepo;
  late LanguageProvider language;
  late SrsProvider srs;
  late GrammarReviewProvider grammar;
  late MistakeProvider mistakes;

  setUp(() async {
    await GetIt.I.reset();
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    // Reset the legacy blobs / migration flags so no prefs->SQLite migration
    // interferes with the DB-seeded rows below.
    await prefs.preferences.setString(LocalStateKeys.srsState, '{}');
    await prefs.preferences.setString(LocalStateKeys.grammarReviewState, '{}');
    await prefs.preferences.setBool('srs.migratedToSqlite.srs', true);
    await prefs.preferences.setBool('srs.migratedToSqlite.grammar', true);

    // One shared in-memory DB for both DAOs so seeded rows are visible to the
    // providers the registry reloads.
    final db = emptyInMemoryCourseDatabase();
    srsDao = SrsStateDao(db);
    mistakeRepo = MistakeRepository(db);

    await srsDao.upsert(
      'srs',
      SrsWord.fresh('w-1'),
      languageCode: LanguageCodes.turkish,
    );
    await srsDao.upsert(
      'srs',
      SrsWord.fresh('fr-w-bonjour'),
      languageCode: LanguageCodes.french,
    );
    await mistakeRepo.replaceAll(
      languageCode: LanguageCodes.french,
      entries: [
        MistakeEntry(
          id: 'm-fr-1',
          lessonId: 'fr-lesson-1',
          stageId: 'fr-stage-1',
          interactionId: 'fr-interaction-1',
          wordId: 'fr-w-bonjour',
          timestamp: DateTime(2026, 9, 8, 10),
        ),
      ],
      dailyCounts: const {},
      masteredTotal: 0,
    );

    language = LanguageProvider(prefs);
    srs = SrsProvider(prefs, LessonLinkStore(prefs), srsDao);
    grammar = GrammarReviewProvider(prefs, LessonLinkStore(prefs), srsDao);
    mistakes = MistakeProvider(prefs)..useRepository(mistakeRepo);

    GetIt.I.registerSingleton<LanguageProvider>(language);
    GetIt.I.registerSingleton<SrsProvider>(srs);
    GetIt.I.registerSingleton<GrammarReviewProvider>(grammar);
    GetIt.I.registerSingleton<MistakeProvider>(mistakes);
    addTearDown(GetIt.I.reset);
  });

  test(
      'reloadAll re-points the queues at the restored language and reloads '
      'the mistake log from the DB', () async {
    // Simulate the restore: the persisted language selection became French.
    await prefs.setString(PrefsConstants.currentLanguage, LanguageCodes.french);

    // Precondition: providers still hold the pre-restore default.
    expect(srs.languageFilter, LanguageCodes.turkish);

    final report =
        await PostRestoreReloadRegistry.withDefaultSteps().reloadAll();

    expect(report.failures, isEmpty);
    expect(language.selectedLanguageCode, LanguageCodes.french);
    expect(srs.languageFilter, LanguageCodes.french);
    expect(srs.state.keys, {'fr-w-bonjour'});
    expect(grammar.languageFilter, LanguageCodes.french);
    expect(mistakes.entries.map((e) => e.id), ['m-fr-1']);
  });

  test('a same-language restore still refreshes the queue from the DB',
      () async {
    await prefs.setString(PrefsConstants.currentLanguage, LanguageCodes.turkish);
    await srs.ensureLoaded();
    expect(srs.state.keys, {'w-1'});

    // Rows appearing in the DB after the cache hydrated must show up after
    // the reload sweep even though the language didn't change (the filter
    // early-return must not skip the refresh).
    await srsDao.upsert(
      'srs',
      SrsWord.fresh('w-late'),
      languageCode: LanguageCodes.turkish,
    );

    final report =
        await PostRestoreReloadRegistry.withDefaultSteps().reloadAll();

    expect(report.failures, isEmpty);
    expect(srs.state.keys, {'w-1', 'w-late'});
  });
}
