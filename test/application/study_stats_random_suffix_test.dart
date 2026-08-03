// Regression: `_randomSuffix` previously used `DateTime.now().millisecond`
// to pick 6 chars, which gave every char the same value (e.g. `777777`) and
// only `~1/1000` entropy. After the fix, suffixes must be effectively
// unique across many samples written in the same millisecond.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/domain/study/study_log.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs appPrefs;
  late StudyStatsProvider provider;
  late StudyLogRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await StreamingSharedPreferences.instance;
    appPrefs = AppPrefs(prefs);
    repo = StudyLogRepository(appPrefs);
    provider = StudyStatsProvider(repo, MistakeProvider(appPrefs));
  });

  tearDown(() async {
    // Reset the StreamingSharedPreferences singleton so the next test sees
    // a fresh store rather than the one this test populated.
    await appPrefs.preferences.clear();
  });

  test('1000 study-log ids are all unique (suffix is random)', () async {
    // Record 1000 logs back-to-back. The id format is
    // `<milliseconds>_<6-char random suffix>`. Even if many logs share the
    // same millisecond, the random suffix must keep ids unique. With the
    // pre-fix `_randomSuffix` using `DateTime.now().millisecond % 36` per
    // char, all 6 chars were the same, dropping entropy to ~1k and
    // producing many collisions across rapid writes.
    for (var i = 0; i < 1000; i++) {
      await provider.recordActivity(
        type: StudyActivityType.lessonComplete,
        lessonId: 'l-$i',
      );
    }

    final logs = await repo.readLogs();
    expect(logs.length, 1000);
    final ids = logs.map((l) => l.id).toSet();
    // Allow at most a couple of collisions from millisecond-only uniqueness
    // (should be 0 with the fix; tolerate ≤1 to avoid flakiness on slow
    // runners).
    expect(ids.length, greaterThanOrEqualTo(999));
  });

  test('recordActivity produces log ids with 6-char random suffix', () async {
    await provider.recordActivity(
      type: StudyActivityType.lessonComplete,
      lessonId: 'l-suffix-shape',
    );
    final logs = await repo.readLogs();
    expect(logs.length, 1);
    final id = logs.first.id;
    // Format: `<epoch_ms>_<6 chars from [a-z0-9]>`
    final parts = id.split('_');
    expect(parts.length, 2);
    expect(parts[1].length, 6);
    expect(RegExp(r'^[a-z0-9]{6}$').hasMatch(parts[1]), isTrue,
        reason: 'suffix should be 6 chars of [a-z0-9], got "${parts[1]}"');
  });
}
