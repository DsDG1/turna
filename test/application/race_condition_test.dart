// Regression tests for race conditions on prefs-backed single-writer keys.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/domain/study/study_log.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    // Start every test at zero so additive writes start from a known value.
    await prefs.preferences.setInt(LocalStateKeys.gems, 0);
  });

  test('GemsProvider serializes concurrent +addGems to a deterministic total',
      () async {
    final gems = GemsProvider(prefs);
    // Fire 10 simultaneous +1 writes. Pre-fix, the read-modify-write
    // window would let several of them see the same `current` and lose
    // deltas. With the write-chain serializing, the final total is 10.
    await Future.wait(List.generate(10, (_) => gems.addGems(1)));
    expect(
      prefs.preferences
          .getInt(LocalStateKeys.gems, defaultValue: -1)
          .getValue(),
      10,
    );
  });

  test('GemsProvider addGems(0) is a no-op even with parallel calls', () async {
    final gems = GemsProvider(prefs);
    await Future.wait([
      gems.addGems(0),
      gems.addGems(0),
      gems.addGems(0),
    ]);
    expect(
      prefs.preferences
          .getInt(LocalStateKeys.gems, defaultValue: -1)
          .getValue(),
      0,
    );
  });

  test(
      'StudyLogRepository serializes concurrent appendLog so lessonCount adds up',
      () async {
    final repo = StudyLogRepository(prefs);
    // Fire 5 simultaneous logs of the same day; lessonCount must equal 5.
    // Use today's date so readLastNDays(1) reads the bucket the logs land in.
    final now = DateTime.now();
    await Future.wait(
      List.generate(
        5,
        (i) => repo.appendLog(
          StudyLog(
            id: 'log-$i',
            timestamp: DateTime(now.year, now.month, now.day, 10, i),
            type: StudyActivityType.lessonComplete,
            lessonId: 'l-$i',
            xpEarned: 10,
            durationSeconds: 60,
            correctCount: 5,
            incorrectCount: 0,
            wordIds: const [],
          ),
        ),
      ),
    );

    final logs = await repo.readLogs();
    expect(logs.length, 5);

    final stats = await repo.readLastNDays(1);
    expect(stats.length, 1);
    expect(stats.first.lessonCount, 5,
        reason: 'serialized writes must accumulate to 5');
    expect(stats.first.correctCount, 25);
    expect(stats.first.totalXp, 50);
  });
}
