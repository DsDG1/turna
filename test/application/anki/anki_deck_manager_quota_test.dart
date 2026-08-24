// Regression tests for the per-day new/review quota counters in
// AnkiDeckManager. `recordCardUnreviewed(wasNewCard: false)` used to be the
// hardcoded call on the undo path, which decremented the wrong counter after
// a new-card answer; and the per-deck clamp at the limit silently lost one
// count per undo at the cap.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late AppPrefs appPrefs;
  late AnkiDeckManager manager;
  late AnkiImportDao importDao;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    appPrefs = AppPrefs(preferences);
    db = emptyInMemoryCourseDatabase();
    importDao = AnkiImportDao(db);
    await importDao.upsert(const AnkiImportRecord(
      importId: 'imp1',
      sourcePath: '/tmp/x.apkg',
      sourceHash: 'hash1',
      importedAt: 1700000000,
    ));
    manager = AnkiDeckManager(
      repo: CourseRepository(db),
      srsProvider: SrsProvider(
        appPrefs,
        LessonLinkStore(appPrefs),
        SrsStateDao(db),
      ),
      importDao: importDao,
      noteDao: AnkiNoteDao(db),
      appPrefs: appPrefs,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('record + undo keep the new and review counters separate', () async {
    await manager.recordCardReviewed(isNewCard: true);
    await manager.recordCardReviewed(isNewCard: true);
    await manager.recordCardReviewed(isNewCard: false);
    expect(manager.newDoneToday, 2);
    expect(manager.reviewDoneToday, 1);

    // Undoing a NEW answer must decrement the new counter, not review.
    await manager.recordCardUnreviewed(wasNewCard: true);
    expect(manager.newDoneToday, 1);
    expect(manager.reviewDoneToday, 1);

    await manager.recordCardUnreviewed(wasNewCard: false);
    expect(manager.newDoneToday, 1);
    expect(manager.reviewDoneToday, 0);
  });

  test('per-deck counters respect the configured limit and undo at the cap',
      () async {
    await importDao.setDailyLimits('imp1', newLimit: 2);
    // StreamingSharedPreferences caches across tests in one file, so all
    // global assertions are deltas, never absolute values.
    final globalNewBefore = manager.newDoneToday;
    await manager.recordCardReviewed(isNewCard: true, importId: 'imp1');
    await manager.recordCardReviewed(isNewCard: true, importId: 'imp1');
    // Clamped at the limit.
    await manager.recordCardReviewed(isNewCard: true, importId: 'imp1');
    expect(
      await manager.remainingForImport('imp1', isNew: true),
      0,
    );
    // Undo at the cap must free a slot (the clamp asymmetry used to eat it).
    await manager.recordCardUnreviewed(wasNewCard: true, importId: 'imp1');
    expect(
      await manager.remainingForImport('imp1', isNew: true),
      1,
    );
    // Global counters untouched by the per-deck path.
    expect(manager.newDoneToday, globalNewBefore);
  });
}
