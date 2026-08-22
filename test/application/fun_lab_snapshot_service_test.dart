import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/fun_lab_snapshot_service.dart';
import 'package:turna/application/fun_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/lesson_progress_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/score_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/streak_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/settings/widgets/settings_fun_section.dart';

import '../helpers/achievement_test_stack.dart';
import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late AppPrefs prefs;
  late SrsStateDao srsDao;
  late SrsProvider srs;
  late GrammarReviewProvider grammar;
  late FunLabSnapshotService service;
  late GemsProvider gems;
  late GameProvider game;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final streaming = await StreamingSharedPreferences.instance;
    for (final key in streaming.getKeys().getValue()) {
      await streaming.remove(key);
    }
    prefs = AppPrefs(streaming);
    db = emptyInMemoryCourseDatabase();
    await db.customSelect('SELECT 1').get();
    srsDao = SrsStateDao(db);
    final links = LessonLinkStore(prefs);
    srs = SrsProvider(prefs, links, srsDao);
    grammar = GrammarReviewProvider(prefs, links, srsDao);
    await Future.wait([srs.ensureLoaded(), grammar.ensureLoaded()]);

    final achievements = AchievementTestStack.build(prefs);
    // Share the lesson-progress instance across the game facade, the
    // snapshot service, and the achievement projector (mirrors DI wiring).
    final lessonProgress = achievements.lessonProgress;
    final mistakes = MistakeProvider(prefs);
    final logs = StudyLogRepository(prefs);
    final stats = StudyStatsProvider(logs, mistakes);
    gems = GemsProvider(prefs);
    game = GameProvider(
      prefs,
      ScoreProvider(prefs),
      StreakProvider(prefs),
      lessonProgress,
    );
    service = FunLabSnapshotService(
      prefs,
      db,
      srsDao,
      srs,
      grammar,
      lessonProgress,
      mistakes,
      links,
      logs,
      stats,
      gems,
      game,
      achievements.service,
    );
  });

  tearDown(() async {
    await db.close();
  });

  SrsWord item(
    String id,
    DateTime due, {
    SrsItemType type = SrsItemType.word,
    bool suspended = false,
    bool buried = false,
  }) {
    return SrsWord(
      wordId: id,
      dueAt: due,
      intervalDays: 12,
      ease: 2.35,
      reps: 4,
      lapses: 1,
      isSuspended: suspended,
      isBuried: buried,
      type: type,
      stability: 8.5,
      difficulty: 4.1,
      fsrsState: 2,
    );
  }

  test('postpones every active queue item by exactly 24 hours', () async {
    final now = DateTime(2026, 8, 5, 9, 30);
    final original = <String, SrsWord>{
      'word': item('word', now.subtract(const Duration(days: 2))),
      'expression': item(
        'expression',
        now.add(const Duration(days: 7)),
        type: SrsItemType.expression,
      ),
      'grammar': item('grammar', now),
      'anki-import-c1':
          item('anki-import-c1', now.add(const Duration(days: 2))),
      'suspended': item('suspended', now, suspended: true),
      'buried': item('buried', now, buried: true),
    };
    await srsDao.upsertBatch('srs', [
      original['word']!,
      original['expression']!,
      original['anki-import-c1']!,
      original['suspended']!,
      original['buried']!,
    ]);
    await srsDao.upsert('grammar', original['grammar']!);
    await db.customStatement('''
      INSERT INTO review_events
        (card_id, queue, reviewed_at, quality, prev_interval_days,
         next_interval_days, prev_ease, next_ease, reps, lapses, type)
      VALUES ('word', 'srs', 1234, 4, 3, 12, 2.3, 2.35, 4, 1, 'word')
    ''');

    final affected =
        await service.postponeAllActiveReviews(const Duration(days: 1));
    expect(affected, 4);

    final loaded = {
      ...await srsDao.loadQueue('srs'),
      ...await srsDao.loadQueue('grammar'),
    };
    for (final id in ['word', 'expression', 'grammar', 'anki-import-c1']) {
      final before = original[id]!;
      final after = loaded[id]!;
      expect(after.dueAt.difference(before.dueAt), const Duration(days: 1));
      expect(after.intervalDays, before.intervalDays);
      expect(after.ease, before.ease);
      expect(after.reps, before.reps);
      expect(after.lapses, before.lapses);
      expect(after.stability, before.stability);
      expect(after.difficulty, before.difficulty);
    }
    expect(loaded['suspended']!.dueAt, original['suspended']!.dueAt);
    expect(loaded['buried']!.dueAt, original['buried']!.dueAt);
    final history = await db
        .customSelect(
          'SELECT reviewed_at, next_interval_days FROM review_events',
        )
        .getSingle();
    expect(history.read<int>('reviewed_at'), 1234);
    expect(history.read<int>('next_interval_days'), 12);
    expect(srs.state['word']!.dueAt, loaded['word']!.dueAt);
    expect(grammar.state['grammar']!.dueAt, loaded['grammar']!.dueAt);
  });

  test('snapshot restores progress, review history and Anki state and remains',
      () async {
    final due = DateTime(2026, 8, 6, 10);
    await srsDao.upsert('srs', item('word', due));
    await db.customStatement('''
      INSERT INTO review_events
        (card_id, queue, reviewed_at, quality, prev_interval_days,
         next_interval_days, prev_ease, next_ease, reps, lapses, type)
      VALUES ('word', 'srs', 111, 4, 3, 12, 2.3, 2.35, 4, 1, 'word')
    ''');
    await db.customStatement('''
      INSERT INTO anki_imports
        (import_id, source_path, source_hash, imported_at)
      VALUES ('imp', 'deck.apkg', 'hash', 1)
    ''');
    await db.customStatement('''
      INSERT INTO anki_cards_meta
        (import_id, card_id, note_id, word_id, suspended, buried_until,
         marked, flag)
      VALUES ('imp', 1, 1, 'anki-imp-c1', 1, 999, 1, 3)
    ''');
    await prefs.preferences.setInt(LocalStateKeys.score, 321);
    await prefs.preferences.setInt(LocalStateKeys.gems, 45);
    await prefs.preferences.setStringList(
      LocalStateKeys.completedLessonIds,
      ['lesson-1'],
    );
    await prefs.preferences.setString(LocalStateKeys.mistakeLog, '[{"x":1}]');
    await prefs.preferences.setString('study.logs', '[{"id":"old"}]');
    await prefs.preferences.setInt('anki.deck.imp.reviewDone.2026-08-05', 8);
    await prefs.preferences.setBool(
      LocalStateKeys.funAllAchievementsUnlocked,
      true,
    );

    final snapshot = await service.createSnapshot();
    expect(snapshot.srsItemCount, 1);

    await prefs.preferences.setInt(LocalStateKeys.score, 99999);
    await prefs.preferences.setInt(LocalStateKeys.gems, 99999);
    await prefs.preferences.setStringList(
      LocalStateKeys.completedLessonIds,
      ['lesson-2'],
    );
    await prefs.preferences.setString(LocalStateKeys.mistakeLog, '[]');
    await prefs.preferences.setString('study.logs', '[]');
    await prefs.preferences.setInt('anki.deck.imp.reviewDone.2026-08-05', 99);
    await prefs.preferences.setInt('anki.deck.imp.newDone.2026-08-05', 7);
    await prefs.preferences.setBool(
      LocalStateKeys.funAllAchievementsUnlocked,
      false,
    );
    await srsDao.upsert('srs', item('word', due.add(const Duration(days: 10))));
    await db.customStatement('DELETE FROM review_events');
    await db.customStatement('''
      UPDATE anki_cards_meta SET suspended = 0, buried_until = NULL,
        marked = 0, flag = 0 WHERE import_id = 'imp' AND card_id = 1
    ''');

    await service.restoreSnapshot();

    expect(
      prefs.preferences
          .getInt(LocalStateKeys.score, defaultValue: 0)
          .getValue(),
      321,
    );
    expect(
      prefs.preferences.getInt(LocalStateKeys.gems, defaultValue: 0).getValue(),
      45,
    );
    expect(
      prefs.preferences.getStringList(LocalStateKeys.completedLessonIds,
          defaultValue: const []).getValue(),
      ['lesson-1'],
    );
    expect(
      prefs.preferences
          .getString(LocalStateKeys.mistakeLog, defaultValue: '')
          .getValue(),
      '[{"x":1}]',
    );
    expect(
      prefs.preferences.getString('study.logs', defaultValue: '').getValue(),
      '[{"id":"old"}]',
    );
    expect(
      prefs.preferences
          .getInt('anki.deck.imp.reviewDone.2026-08-05', defaultValue: 0)
          .getValue(),
      8,
    );
    expect(
      prefs.preferences.getKeys().getValue(),
      isNot(contains('anki.deck.imp.newDone.2026-08-05')),
    );
    expect(
      prefs.preferences
          .getBool(LocalStateKeys.funAllAchievementsUnlocked,
              defaultValue: false)
          .getValue(),
      isTrue,
    );
    expect((await srsDao.loadQueue('srs'))['word']!.dueAt, due);
    final history = await db.customSelect('SELECT * FROM review_events').get();
    expect(history, hasLength(1));
    expect(history.single.read<int>('reviewed_at'), 111);
    final anki = await db
        .customSelect(
          "SELECT suspended, buried_until, marked, flag FROM anki_cards_meta "
          "WHERE import_id = 'imp' AND card_id = 1",
        )
        .getSingle();
    expect(anki.read<int>('suspended'), 1);
    expect(anki.read<int?>('buried_until'), 999);
    expect(anki.read<int>('marked'), 1);
    expect(anki.read<int>('flag'), 3);
    expect(await service.loadMeta(), isNotNull,
        reason: 'restore keeps the reusable checkpoint');
  });

  test('replace and delete are persistent and content changes block restore',
      () async {
    await service.createSnapshot();
    final first = await service.loadMeta();
    expect(first, isNotNull);

    await Future<void>.delayed(const Duration(milliseconds: 2));
    await service.createSnapshot();
    final replaced = await service.loadMeta();
    expect(
      replaced!.createdAt.millisecondsSinceEpoch,
      greaterThanOrEqualTo(first!.createdAt.millisecondsSinceEpoch),
    );

    await db.customStatement(
      "INSERT INTO course_meta (key, value) VALUES ('contentVersion', 'new')",
    );
    expect(
      service.restoreSnapshot,
      throwsA(isA<FunLabSnapshotContentChanged>()),
    );

    await service.deleteSnapshot();
    expect(await service.loadMeta(), isNull);
  });

  test('all-achievements cheat only sets the display override', () async {
    await prefs.preferences.setInt(LocalStateKeys.score, 17);
    await prefs.preferences.setInt(LocalStateKeys.streak, 2);
    await prefs.preferences.setInt(LocalStateKeys.lessonsCompleted, 3);
    await prefs.preferences.setInt(LocalStateKeys.perfectLessons, 1);
    await prefs.preferences.setInt(LocalStateKeys.wordsLearned, 9);
    await prefs.preferences.setStringList(
      LocalStateKeys.achievements,
      ['xp_1000'],
    );
    await service.createSnapshot();
    final provider = FunProvider(prefs, game, gems, service);
    while (!provider.snapshotLoaded) {
      await Future<void>.delayed(Duration.zero);
    }

    await provider.cheatUnlockAllAchievements();

    expect(provider.allAchievementsUnlocked, isTrue);
    expect(
      prefs.preferences
          .getInt(LocalStateKeys.score, defaultValue: 0)
          .getValue(),
      17,
    );
    expect(
      prefs.preferences
          .getInt(LocalStateKeys.streak, defaultValue: 0)
          .getValue(),
      2,
    );
    expect(
      prefs.preferences
          .getInt(LocalStateKeys.lessonsCompleted, defaultValue: 0)
          .getValue(),
      3,
    );
    expect(
      prefs.preferences.getStringList(LocalStateKeys.achievements,
          defaultValue: const []).getValue(),
      ['xp_1000'],
      reason: 'normal milestone ids and rewards are not pre-consumed',
    );
  });

  testWidgets('achievement override is display-only and keeps v2 state intact',
      (tester) async {
    await prefs.preferences.setInt(LocalStateKeys.score, 17);
    await prefs.preferences.setInt(LocalStateKeys.streak, 2);
    await prefs.preferences.setInt(LocalStateKeys.lessonsCompleted, 3);
    await prefs.preferences.setInt(LocalStateKeys.perfectLessons, 1);
    await prefs.preferences.setInt(LocalStateKeys.wordsLearned, 9);
    await prefs.preferences.setString(
      LocalStateKeys.achievementsStateV2,
      '{"schemaVersion":2,"unlockedTiers":{},'
      '"updatedAt":"2026-08-01T00:00:00","migrationDiagnostics":[]}',
    );
    await service.createSnapshot();
    final fun = FunProvider(prefs, game, gems, service);
    await tester.runAsync(() async {
      while (!fun.snapshotLoaded) {
        await Future<void>.delayed(Duration.zero);
      }
      await fun.cheatUnlockAllAchievements();
    });

    // The Fun Lab preview never consumes real unlocks: the v2 state document
    // is untouched by the cheat.
    expect(
      prefs.preferences
          .getString(LocalStateKeys.achievementsStateV2, defaultValue: '')
          .getValue(),
      contains('"schemaVersion":2'),
      reason: 'fun preview must not rewrite the real v2 achievement state',
    );
    expect(fun.allAchievementsUnlocked, isTrue);
  });

  testWidgets('dangerous action without checkpoint prompts to create one',
      (tester) async {
    final fun = FunProvider(prefs, game, gems, service);
    await tester.runAsync(() async {
      while (!fun.snapshotLoaded) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<FunProvider>.value(
        value: fun,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: SettingsFunSection()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(AppStrings.settingsFunSnapshotEmpty), findsOneWidget);

    final maxScore = find.text(AppStrings.settingsFunMaxScoreTitle);
    await tester.ensureVisible(maxScore);
    await tester.tap(maxScore);
    await tester.pumpAndSettle();
    expect(
      find.text(AppStrings.settingsFunSnapshotRequiredTitle),
      findsOneWidget,
    );
    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();
    expect(
      prefs.preferences.getKeys().getValue(),
      isNot(contains(LocalStateKeys.score)),
    );
  });

  testWidgets('existing checkpoint exposes restore and delete actions',
      (tester) async {
    await service.createSnapshot();
    final fun = FunProvider(prefs, game, gems, service);
    await tester.runAsync(() async {
      while (!fun.snapshotLoaded) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<FunProvider>.value(
        value: fun,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: SettingsFunSection()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
        find.text(AppStrings.settingsFunSnapshotRestoreTitle), findsOneWidget);
    expect(
        find.text(AppStrings.settingsFunSnapshotDeleteTitle), findsOneWidget);
    expect(find.text(AppStrings.settingsFunPostponeTitle), findsOneWidget);
  });
}
