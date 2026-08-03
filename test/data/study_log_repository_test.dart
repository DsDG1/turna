import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/domain/study/study_log.dart';
import 'package:turna/service/locator.dart';

// StudyLogRepository uses private key constants; mirror them here for tests.
const _logsKey = 'study.logs';
const _recentKey = 'study.logs.recent';
const _dailyStatsKey = 'study.dailyStats';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late StudyLogRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    // Reset the keys touched by StudyLogRepository to avoid cross-test leakage
    // from the cached StreamingSharedPreferences instance.
    await prefs.preferences.setString(_logsKey, '[]');
    await prefs.preferences.setString(_recentKey, '[]');
    await prefs.preferences.setString(_dailyStatsKey, '{}');
    repo = StudyLogRepository(prefs);
  });

  StudyLog makeLog({
    required String id,
    required DateTime timestamp,
    StudyActivityType type = StudyActivityType.lessonComplete,
    String? lessonId,
    int xpEarned = 10,
    int durationSeconds = 60,
    int correctCount = 5,
    int incorrectCount = 0,
  }) =>
      StudyLog(
        id: id,
        timestamp: timestamp,
        type: type,
        lessonId: lessonId,
        xpEarned: xpEarned,
        durationSeconds: durationSeconds,
        correctCount: correctCount,
        incorrectCount: incorrectCount,
      );

  group('appendLog and readLogs', () {
    test('stores and retrieves a single log', () async {
      final now = DateTime.now();
      await repo.appendLog(
        makeLog(id: 'log-1', timestamp: now, lessonId: 'l-1'),
      );

      final logs = await repo.readLogs();
      expect(logs, hasLength(1));
      expect(logs.first.id, 'log-1');
    });

    test('filters logs by date range', () async {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      final lastWeek = today.subtract(const Duration(days: 7));

      await repo.appendLog(makeLog(id: 'today', timestamp: today));
      await repo.appendLog(makeLog(id: 'yesterday', timestamp: yesterday));
      await repo.appendLog(makeLog(id: 'last-week', timestamp: lastWeek));

      final sinceYesterday = await repo.readLogs(
          since: yesterday.subtract(const Duration(hours: 1)));
      expect(sinceYesterday.map((l) => l.id).toSet(), {'today', 'yesterday'});

      final untilYesterday = await repo.readLogs(
          until: yesterday.subtract(const Duration(hours: 1)));
      expect(
          untilYesterday.map((l) => l.id).toSet(), {'yesterday', 'last-week'});
    });

    test('filters logs by activity type', () async {
      final now = DateTime.now();
      await repo.appendLog(
        makeLog(
            id: 'lesson',
            timestamp: now,
            type: StudyActivityType.lessonComplete),
      );
      await repo.appendLog(
        makeLog(
            id: 'review', timestamp: now, type: StudyActivityType.srsReview),
      );

      final reviews = await repo.readLogs(type: StudyActivityType.srsReview);
      expect(reviews.map((l) => l.id), ['review']);
    });

    test('readLogs caches the merged set and invalidates on append', () async {
      final now = DateTime.now();
      await repo.appendLog(makeLog(id: 'log-1', timestamp: now));

      // First read populates the merged-log cache.
      final first = await repo.readLogs();
      expect(first, hasLength(1));

      // A second read with no filter returns a fresh (defensive) copy with the
      // same contents — callers can mutate it without corrupting the cache.
      final second = await repo.readLogs();
      expect(second, hasLength(1));
      expect(identical(first, second), isFalse);
      second.clear();
      // Cache is untouched by the caller's mutation.
      final third = await repo.readLogs();
      expect(third, hasLength(1));

      // An append invalidates the cache so the next read reflects new data.
      await repo.appendLog(makeLog(id: 'log-2', timestamp: now));
      final afterAppend = await repo.readLogs();
      expect(afterAppend.map((l) => l.id).toSet(), {'log-1', 'log-2'});
    });

    test('clearAll invalidates the merged-log cache', () async {
      final now = DateTime.now();
      await repo.appendLog(makeLog(id: 'log-1', timestamp: now));
      expect(await repo.readLogs(), hasLength(1));

      await repo.clearAll();
      expect(await repo.readLogs(), isEmpty);
    });
  });

  group('90-day purge', () {
    test('drops logs older than 90 days while keeping recent ones', () async {
      final today = DateTime.now();
      final old = today.subtract(const Duration(days: 100));

      await repo.appendLog(makeLog(id: 'old', timestamp: old));
      await repo.appendLog(makeLog(id: 'recent', timestamp: today));

      final logs = await repo.readLogs();
      expect(logs.map((l) => l.id).toSet(), {'recent'});
    });
  });

  group('dailyStats aggregation', () {
    test('aggregates xp, duration, correct/incorrect, lesson count', () async {
      final today = DateTime.now();
      await repo.appendLog(
        makeLog(
          id: 'log-1',
          timestamp: today,
          xpEarned: 15,
          durationSeconds: 120,
          correctCount: 8,
          incorrectCount: 2,
        ),
      );
      await repo.appendLog(
        makeLog(
          id: 'log-2',
          timestamp: today,
          xpEarned: 10,
          durationSeconds: 60,
          correctCount: 5,
          incorrectCount: 0,
        ),
      );
      await repo.appendLog(
        makeLog(
          id: 'review-1',
          timestamp: today,
          type: StudyActivityType.srsReview,
          xpEarned: 5,
          durationSeconds: 30,
          correctCount: 3,
          incorrectCount: 1,
        ),
      );

      final stats = await repo.readLastNDays(1);
      expect(stats, hasLength(1));
      expect(stats.first.totalXp, 30);
      expect(stats.first.totalDurationSeconds, 210);
      expect(stats.first.correctCount, 16);
      expect(stats.first.incorrectCount, 3);
      expect(stats.first.lessonCount, 2);
      expect(stats.first.reviewCount, 1);
      expect(stats.first.accuracy, closeTo(16 / 19, 0.001));
    });

    test('readLastNDays returns default stats for days with no logs', () async {
      final stats = await repo.readLastNDays(3);
      expect(stats, hasLength(3));
      expect(stats.every((s) => s.totalXp == 0), isTrue);
    });
  });

  group('clearAll', () {
    test('removes all logs and daily stats', () async {
      final now = DateTime.now();
      await repo.appendLog(makeLog(id: 'log-1', timestamp: now));
      await repo.clearAll();

      expect(await repo.readLogs(), isEmpty);
      expect((await repo.readAllDailyStats()).entries, isEmpty);
    });
  });

  group('write-chain serialization', () {
    test('serializes concurrent appends so daily stats accumulate correctly',
        () async {
      final today = DateTime.now();
      await Future.wait(
        List.generate(
          10,
          (i) => repo.appendLog(
            makeLog(
              id: 'log-$i',
              timestamp: today,
              xpEarned: 1,
              durationSeconds: 1,
              correctCount: 1,
              incorrectCount: 0,
            ),
          ),
        ),
      );

      final logs = await repo.readLogs();
      expect(logs.length, 10);

      final stats = await repo.readLastNDays(1);
      expect(stats.first.totalXp, 10);
      expect(stats.first.lessonCount, 10);
    });

    // writeFailures is the observable surface for otherwise-silent write
    // failures (SharedPreferences I/O error / encode failure). It must start
    // at zero and stay zero across successful writes — the counter only moves
    // when a chained op actually throws.
    test('writeFailures starts at zero and stays zero on successful writes',
        () async {
      expect(repo.writeFailures, 0);

      final now = DateTime.now();
      await repo.appendLog(makeLog(id: 'ok-1', timestamp: now));
      await repo.clearAll();

      expect(repo.writeFailures, 0);
    });
  });

  group('recent queue (ADR 0012)', () {
    test('append stays in recent until cap, still readable', () async {
      final now = DateTime.now();
      await repo.appendLog(makeLog(id: 'r1', timestamp: now));

      final recentRaw = prefs.preferences
          .getString(_recentKey, defaultValue: '[]')
          .getValue();
      expect(recentRaw.contains('r1'), isTrue);

      final mainRaw =
          prefs.preferences.getString(_logsKey, defaultValue: '[]').getValue();
      expect(mainRaw, '[]');

      final logs = await repo.readLogs();
      expect(logs.map((l) => l.id), ['r1']);
    });

    test('reaching recentCap merges into main and clears recent', () async {
      final now = DateTime.now();
      const cap = StudyLogRepository.recentCap;
      for (var i = 0; i < cap; i++) {
        await repo.appendLog(
          makeLog(id: 'bulk-$i', timestamp: now, xpEarned: 1),
        );
      }

      final recentRaw = prefs.preferences
          .getString(_recentKey, defaultValue: '[]')
          .getValue();
      expect(recentRaw, '[]');

      final logs = await repo.readLogs();
      expect(logs.length, cap);
    });

    test('flushRecent merges pending entries', () async {
      final now = DateTime.now();
      await repo.appendLog(makeLog(id: 'pending', timestamp: now));
      await repo.flushRecent();

      final recentRaw = prefs.preferences
          .getString(_recentKey, defaultValue: '[]')
          .getValue();
      expect(recentRaw, '[]');

      final mainRaw =
          prefs.preferences.getString(_logsKey, defaultValue: '[]').getValue();
      expect(mainRaw.contains('pending'), isTrue);
    });

    test('1000 appends preserve all ids (cap merge)', () async {
      final now = DateTime.now();
      final sw = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        await repo.appendLog(
          makeLog(id: 'n-$i', timestamp: now, xpEarned: 1, durationSeconds: 1),
        );
      }
      sw.stop();
      // ignore: avoid_print
      print('StudyLog 1000 appends: ${sw.elapsedMilliseconds}ms');

      final logs = await repo.readLogs();
      expect(logs.length, 1000);
    });
  });

  group('corruption handling', () {
    test('returns empty dailyStats when JSON is corrupted', () async {
      await prefs.preferences.setString(_dailyStatsKey, 'not-json');
      final stats = await repo.readAllDailyStats();
      expect(stats, isEmpty);
    });

    test('returns empty logs when JSON is corrupted', () async {
      await prefs.preferences.setString(_logsKey, 'not-json');
      final logs = await repo.readLogs();
      expect(logs, isEmpty);
    });

    test(
        'appendLog still works after corrupted logs (reads empty, then writes)',
        () async {
      await prefs.preferences.setString(_logsKey, 'not-json');
      await repo.appendLog(makeLog(id: 'recovered', timestamp: DateTime.now()));
      final logs = await repo.readLogs();
      expect(logs, hasLength(1));
      expect(logs.single.id, 'recovered');
    });
  });
}
