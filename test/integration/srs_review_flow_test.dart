// SRS review path: due → review → dueCount drops → survives provider restart.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/core/sm2.dart';
import 'package:varnamala/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

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
    final dao = emptySrsStateDao();
    final srs = SrsProvider(prefs, link, dao);

    srs.registerWord('w-due-1');
    srs.registerWord('w-due-2');
    expect(srs.dueCount, 2);

    await srs.reviewWord('w-due-1', ReviewGrade.known.sm2);
    expect(srs.dueCount, 1);

    // "Restart" = new provider instance on the same DB.
    final restarted = SrsProvider(prefs, LessonLinkStore(prefs), dao);
    await restarted.ensureLoaded();
    expect(restarted.state.containsKey('w-due-1'), isTrue);
    expect(restarted.state.containsKey('w-due-2'), isTrue);
    // Good review schedules out; only unseen/due remain.
    expect(restarted.dueCount, 1);
    expect(restarted.getDueWords().single.wordId, 'w-due-2');
  });

  test('a successful review records a per-card review event', () async {
    final link = LessonLinkStore(prefs);
    final srsDao = emptySrsStateDao();
    final reviewDao = emptyReviewHistoryDao();
    final srs = SrsProvider(prefs, link, srsDao);
    srs.setReviewHistoryDaoForTesting(reviewDao);

    srs.registerWord('w-1');
    await srs.reviewWord('w-1', ReviewGrade.known.sm2);

    final events = await reviewDao.eventsForCard('w-1');
    expect(events, hasLength(1));
    expect(events.single.quality, ReviewGrade.known.sm2);
    expect(events.single.recalled, isTrue);
    expect(events.single.prevIntervalDays, 1); // fresh default
    // FSRS (ADR 0028) schedules from stability — not a fixed SM-2 1-day step.
    expect(events.single.nextIntervalDays, greaterThanOrEqualTo(1));
  });

  test('a failed review records an event with recalled=false and a lapse',
      () async {
    final link = LessonLinkStore(prefs);
    final srsDao = emptySrsStateDao();
    final reviewDao = emptyReviewHistoryDao();
    final srs = SrsProvider(prefs, link, srsDao);
    srs.setReviewHistoryDaoForTesting(reviewDao);

    srs.registerWord('w-1');
    await srs.reviewWord('w-1', ReviewGrade.unknown.sm2);

    final events = await reviewDao.eventsForCard('w-1');
    expect(events, hasLength(1));
    expect(events.single.recalled, isFalse);
    expect(events.single.lapses, 1);
  });
}
