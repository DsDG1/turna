// SRS review path: due → review → dueCount drops → survives provider restart.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/core/sm2.dart';
import 'package:varnamala/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.preferences.setString(LocalStateKeys.srsState, '{}');
  });

  test('review lowers dueCount and persists across restart', () async {
    final link = LessonLinkStore(prefs);
    final srs = SrsProvider(prefs, link);

    srs.registerWord('w-due-1');
    srs.registerWord('w-due-2');
    expect(srs.dueCount, 2);

    await srs.reviewWord('w-due-1', ReviewQuality.good.sm2);
    expect(srs.dueCount, 1);

    // "Restart" = new provider instance on same prefs.
    final restarted = SrsProvider(prefs, LessonLinkStore(prefs));
    expect(restarted.state.containsKey('w-due-1'), isTrue);
    expect(restarted.state.containsKey('w-due-2'), isTrue);
    // Good review schedules out; only unseen/due remain.
    expect(restarted.dueCount, 1);
    expect(restarted.getDueWords().single.wordId, 'w-due-2');
  });
}
