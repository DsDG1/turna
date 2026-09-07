import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/lesson_progress_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/score_provider.dart';
import 'package:turna/application/streak_provider.dart';
import 'package:turna/application/study_session/session_settlement_service.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/domain/achievements/achievement_unlock_result.dart';
import 'package:turna/domain/study/study_log.dart';
import '../../helpers/achievement_test_stack.dart';
import 'package:turna/service/locator.dart';

/// Capture-only recording overrides over the real providers, sharing one
/// trace list so tests can pin the write ORDER across writers.
class _Trace {
  final List<String> events = [];
}

class _RecordingGameProvider extends GameProvider {
  _RecordingGameProvider(AppPrefs prefs, this.trace)
      : super(
          prefs,
          ScoreProvider(prefs),
          StreakProvider(prefs),
          LessonProgressProvider(prefs),
        );

  final _Trace trace;

  @override
  Future<int> awardXP(
    XPEvent event, {
    double multiplier = 1.0,
    bool notify = true,
  }) async {
    final awarded = await super.awardXP(event, multiplier: multiplier);
    trace.events.add('xp:${event.name}:${multiplier.toStringAsFixed(1)}:$awarded');
    return awarded;
  }
}

class _RecordingGemsProvider extends GemsProvider {
  _RecordingGemsProvider(super.prefs, this.trace);

  final _Trace trace;
  final List<String?> eventIds = [];

  @override
  Future<void> earnGems(
    GemEvent event, {
    String? eventId,
    int? amount,
  }) async {
    eventIds.add(eventId);
    trace.events.add('gems:${event.name}:$eventId');
    await super.earnGems(event, eventId: eventId);
  }
}

class _RecordingStudyStatsProvider extends StudyStatsProvider {
  _RecordingStudyStatsProvider(AppPrefs prefs, this.trace)
      : super(StudyLogRepository(prefs), MistakeProvider(prefs));

  final _Trace trace;
  final List<({int xp, int seconds, int correct, int incorrect})> activities =
      [];

  @override
  Future<void> recordActivity({
    required StudyActivityType type,
    String? lessonId,
    int xpEarned = 0,
    int durationSeconds = 0,
    int correctCount = 0,
    int incorrectCount = 0,
    List<String> wordIds = const [],
  }) async {
    activities.add((
      xp: xpEarned,
      seconds: durationSeconds,
      correct: correctCount,
      incorrect: incorrectCount,
    ));
    trace.events.add('study:${type.name}:$xpEarned');
  }
}

class _RecordingAchievementService extends AchievementService {
  _RecordingAchievementService(AchievementTestStack stack, this.trace)
      : super(
          stack.stateRepository,
          stack.projector,
          stack.migrationService,
          stack.gemsProvider,
        );

  final _Trace trace;
  final List<int> sessions = [];

  @override
  Future<List<AchievementUnlockResult>> recordReviewSession({
    required int cardsAnswered,
  }) async {
    sessions.add(cardsAnswered);
    trace.events.add('achievements:$cardsAnswered');
    return const [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late _Trace trace;
  late _RecordingGameProvider game;
  late _RecordingGemsProvider gems;
  late _RecordingStudyStatsProvider study;
  late _RecordingAchievementService achievements;
  late SessionSettlementService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    trace = _Trace();
    game = _RecordingGameProvider(prefs, trace);
    gems = _RecordingGemsProvider(prefs, trace);
    study = _RecordingStudyStatsProvider(prefs, trace);
    achievements =
        _RecordingAchievementService(AchievementTestStack.build(prefs), trace);
    service = SessionSettlementService(
      game: game,
      gems: gems,
      study: study,
      achievements: achievements,
    );
  });

  Future<int> settleSrs({
    int remembered = 8,
    int forgotten = 2,
    String sequence = 'seq-1',
    SessionSettlementSource source = SessionSettlementSource.srs,
  }) {
    return service.settle(
      source: source,
      sessionSequence: sequence,
      remembered: remembered,
      forgotten: forgotten,
      elapsed: const Duration(minutes: 3),
    );
  }

  test('settles XP → gems → study log → achievements with real writer math',
      () async {
    final xp = await settleSrs();

    // XPEvent.srsReviewSession base 5 × 10 answered cards.
    expect(xp, 50);
    expect(trace.events, [
      'xp:srsReviewSession:10.0:50',
      'gems:srsReviewSession:earn:srsSession:'
          '${GemRewardEventIds.localDay(DateTime.now())}:seq-1',
      'study:srsReview:50',
      'achievements:10',
    ]);
    expect(study.activities.single,
        (xp: 50, seconds: 180, correct: 8, incorrect: 2));
  });

  test('anki source scopes the gem idempotency key per source', () async {
    await settleSrs(source: SessionSettlementSource.anki, sequence: 'seq-9');

    expect(gems.eventIds.single, contains('earn:ankiSession:'));
    expect(gems.eventIds.single, contains(':seq-9'));
  });

  test('distinct sessions produce distinct gem idempotency keys', () async {
    await settleSrs(sequence: 'seq-1');
    await settleSrs(sequence: 'seq-2');

    expect(gems.eventIds.toSet().length, 2);
  });

  test('without a game writer the performance-based XP fallback applies',
      () async {
    final service = SessionSettlementService(
      gems: gems,
      study: study,
      achievements: achievements,
    );

    final xp = await service.settle(
      source: SessionSettlementSource.srs,
      sessionSequence: 'seq-1',
      remembered: 8,
      forgotten: 2,
      elapsed: const Duration(minutes: 3),
    );

    expect(xp, 8 * 10 + 2 * 2);
    expect(study.activities.single.xp, 84);
  });

  test('an empty session writes nothing', () async {
    final xp = await settleSrs(remembered: 0, forgotten: 0);

    expect(xp, 0);
    expect(trace.events, isEmpty);
    expect(gems.eventIds, isEmpty);
    expect(study.activities, isEmpty);
    expect(achievements.sessions, isEmpty);
  });

  test('a failing writer never breaks the completion flow', () async {
    final failing = SessionSettlementService(
      game: game,
      gems: _ThrowingGemsProvider(prefs),
      study: study,
      achievements: achievements,
    );

    final xp = await failing.settle(
      source: SessionSettlementSource.anki,
      sessionSequence: 'seq-1',
      remembered: 3,
      forgotten: 1,
      elapsed: const Duration(minutes: 1),
    );

    // The failure is logged and swallowed and settle() still reports the
    // XP already awarded; writes after the failed writer are skipped (the
    // same fail-fast semantics both hand-rolled pages had).
    expect(xp, 5 * 4);
    expect(trace.events.first, startsWith('xp:srsReviewSession:'));
    expect(trace.events.where((e) => e.startsWith('gems:')), isEmpty);
    expect(achievements.sessions, isEmpty);
  });
}

class _ThrowingGemsProvider extends GemsProvider {
  _ThrowingGemsProvider(super.prefs);

  @override
  Future<void> earnGems(
    GemEvent event, {
    String? eventId,
    int? amount,
  }) async {
    throw StateError('ledger unavailable');
  }
}
