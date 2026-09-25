// Dart imports:
import 'dart:async';

// Plan P3 failure-injection tests: a course-scope switch must either fully
// apply or leave the app exactly on the previous language — scope, content
// store, and every practice filter move together or not at all.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/domain/repositories/i_study_log_repository.dart';
import 'package:turna/domain/study/daily_stats.dart';
import 'package:turna/domain/study/study_log.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

class _NoopStudyLogRepository implements IStudyLogRepository {
  @override
  Future<void> appendLog(StudyLog log) async {}

  @override
  Future<Map<String, DailyStudyStats>> readAllDailyStats(
      {String? languageCode}) async {
    return {};
  }

  @override
  Future<DailyStudyStats?> readDailyStats(DateTime date,
      {String? languageCode}) async {
    return null;
  }

  @override
  Future<List<StudyLog>> readLogs({
    DateTime? since,
    DateTime? until,
    StudyActivityType? type,
    String? languageCode,
  }) async {
    return [];
  }

  @override
  Future<List<DailyStudyStats>> readLastNDays(int n,
      {String? languageCode}) async {
    return [];
  }

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> reloadFromPrefs() async {}

  @override
  Future<void> deleteByLanguage(String languageCode) async {}
}

/// Records every filter call and optionally fails for one target language —
/// the failure-injection seam for the practice-language cascade.
class _RecordingSrsProvider extends SrsProvider {
  _RecordingSrsProvider(super.prefs, super.linkStore, super.dao);

  final calls = <String?>[];
  String? failFor;

  /// Test timing control: when set, each call parks on this completer
  /// before deciding (records [hitGate] so the test knows it arrived).
  Completer<void>? gate;
  bool hitGate = false;

  @override
  Future<void> setLanguageFilter(String? languageCode) async {
    final g = gate;
    if (g != null) {
      hitGate = true;
      await g.future;
    }
    calls.add(languageCode);
    if (languageCode == failFor) {
      throw StateError('injected SRS sync failure');
    }
  }
}

class _RecordingGrammarProvider extends GrammarReviewProvider {
  _RecordingGrammarProvider(super.prefs, super.linkStore, super.dao);

  final calls = <String?>[];
  String? failFor;

  @override
  Future<void> setLanguageFilter(String? languageCode) async {
    calls.add(languageCode);
    if (languageCode == failFor) {
      throw StateError('injected grammar sync failure');
    }
  }
}

class _RecordingMistakeProvider extends MistakeProvider {
  _RecordingMistakeProvider(super.prefs);

  final calls = <String?>[];
  String? failFor;

  @override
  Future<void> setLanguage(String code) async {
    calls.add(code);
    if (code == failFor) {
      throw StateError('injected mistake sync failure');
    }
  }
}

class _RecordingStatsProvider extends StudyStatsProvider {
  _RecordingStatsProvider(super.repository, super.mistakeProvider);

  final calls = <String?>[];
  String? failFor;

  @override
  void setLanguage(String code) {
    calls.add(code);
    if (code == failFor) {
      throw StateError('injected stats sync failure');
    }
  }
}

class _RecordingLanguageProvider extends LanguageProvider {
  _RecordingLanguageProvider(super.prefs);

  final cached = <String?>[];
  String? failCacheFor;

  @override
  Future<void> cacheLanguage() async {
    if (selectedLanguageCode == failCacheFor) {
      throw StateError('injected preference write failure');
    }
    cached.add(selectedLanguageCode);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late AppPrefs prefs;
  late CourseProvider provider;
  late _RecordingSrsProvider srs;
  late _RecordingGrammarProvider grammar;
  late _RecordingMistakeProvider mistakes;
  late _RecordingStatsProvider stats;
  late _RecordingLanguageProvider language;

  setUp(() async {
    LanguageContentStore.resetForTest();
    CourseLoader.clearDatabaseOverride();
    db = await seedInMemoryCourseDb();

    SharedPreferences.setMockInitialValues({});
    prefs = AppPrefs(await StreamingSharedPreferences.instance);

    srs = _RecordingSrsProvider(
      prefs,
      LessonLinkStore(prefs),
      SrsStateDao(db),
    );
    grammar = _RecordingGrammarProvider(
      prefs,
      LessonLinkStore(prefs),
      SrsStateDao(db),
    );
    mistakes = _RecordingMistakeProvider(prefs);
    stats = _RecordingStatsProvider(_NoopStudyLogRepository(), mistakes);
    language = _RecordingLanguageProvider(prefs);

    getIt.registerSingleton<SrsProvider>(srs);
    getIt.registerSingleton<GrammarReviewProvider>(grammar);
    getIt.registerSingleton<MistakeProvider>(mistakes);
    getIt.registerSingleton<StudyStatsProvider>(stats);
    getIt.registerSingleton<LanguageProvider>(language);

    await prefs.setString(PrefsConstants.courseScope, '');
    provider = CourseProvider(prefs);
    await provider.load();
    expect(provider.scope, const BuiltinCourseScope('tr'),
        reason: 'fixture starts on the turkish builtin course');
  });

  tearDown(() async {
    LanguageContentStore.resetForTest();
    LanguageContentStore.debugLoadFailureForCode = null;
    CourseLoader.clearDatabaseOverride();
    await getIt.reset();
    await db.close();
  });

  Future<String> persistedScopeWire() async => prefs.preferences
      .getString(PrefsConstants.courseScope, defaultValue: '')
      .getValue();

  void expectEverythingStillTurkish(String reason) {
    expect(provider.scope, const BuiltinCourseScope('tr'), reason: reason);
    expect(LanguageContentStore.activeCode, 'tr',
        reason: '$reason (content store)');
    expect(language.selectedLanguageCode, 'tr',
        reason: '$reason (language provider)');
    expect(srs.calls.last, 'tr', reason: '$reason (SRS filter)');
    expect(grammar.calls.last, 'tr', reason: '$reason (grammar filter)');
    expect(mistakes.calls.last, 'tr', reason: '$reason (mistake filter)');
    expect(stats.calls.last, 'tr', reason: '$reason (stats filter)');
  }

  test('a failed content load refuses the switch with no state touched',
      () async {
    LanguageContentStore.debugLoadFailureForCode = 'fr';

    await expectLater(
      provider.setScope(const BuiltinCourseScope('fr')),
      throwsA(isA<CourseScopeSwitchException>()),
    );

    expectEverythingStillTurkish('switch refused before any commit');
    expect(await persistedScopeWire(), isNot('course-scope:v1:builtin:fr'),
        reason: 'the preference never names the refused language');
    expect(srs.calls, isNot(contains('fr')),
        reason: 'phase 1 refuses before any provider sees the new language');
  });

  test('an SRS sync failure rolls scope, content and filters back', () async {
    srs.failFor = 'fr';

    await expectLater(
      provider.setScope(const BuiltinCourseScope('fr')),
      throwsA(isA<CourseScopeSwitchException>()),
    );

    expectEverythingStillTurkish('SRS failure rolled back');
    expect(await persistedScopeWire(), 'course-scope:v1:builtin:tr');
    expect(srs.calls, contains('fr'),
        reason: 'the failed attempt is visible in the call log');
  });

  test('a grammar sync failure rolls everything back', () async {
    grammar.failFor = 'fr';

    await expectLater(
      provider.setScope(const BuiltinCourseScope('fr')),
      throwsA(isA<CourseScopeSwitchException>()),
    );

    expectEverythingStillTurkish('grammar failure rolled back');
    expect(await persistedScopeWire(), 'course-scope:v1:builtin:tr');
  });

  test('a mistake sync failure rolls everything back', () async {
    mistakes.failFor = 'fr';

    await expectLater(
      provider.setScope(const BuiltinCourseScope('fr')),
      throwsA(isA<CourseScopeSwitchException>()),
    );

    expectEverythingStillTurkish('mistake failure rolled back');
    expect(await persistedScopeWire(), 'course-scope:v1:builtin:tr');
  });

  test('a stats sync failure rolls everything back', () async {
    stats.failFor = 'fr';

    await expectLater(
      provider.setScope(const BuiltinCourseScope('fr')),
      throwsA(isA<CourseScopeSwitchException>()),
    );

    expectEverythingStillTurkish('stats failure rolled back');
    expect(await persistedScopeWire(), 'course-scope:v1:builtin:tr');
  });

  test('a failed preference write participates in the rollback', () async {
    language.failCacheFor = 'fr';

    await expectLater(
      provider.setScope(const BuiltinCourseScope('fr')),
      throwsA(isA<CourseScopeSwitchException>()),
    );

    expectEverythingStillTurkish('preference write failure rolled back');
    expect(await persistedScopeWire(), 'course-scope:v1:builtin:tr');
    // The rollback's cacheLanguage for 'tr' succeeded and was awaited.
    expect(language.cached, contains('tr'));
    expect(language.cached, isNot(contains('fr')));
  });

  test('a successful switch moves every consumer together', () async {
    await provider.setScope(const BuiltinCourseScope('fr'));

    expect(provider.scope, const BuiltinCourseScope('fr'));
    expect(LanguageContentStore.activeCode, 'fr');
    expect(language.selectedLanguageCode, 'fr');
    expect(await persistedScopeWire(), 'course-scope:v1:builtin:fr');
    expect(srs.calls.last, 'fr');
    expect(grammar.calls.last, 'fr');
    expect(mistakes.calls.last, 'fr');
    expect(stats.calls.last, 'fr');
  });

  test('rapid consecutive switches serialize: the queued one sees the rollback',
      () async {
    // Park the first switch inside its SRS sync, fire the second switch
    // while the first is still in flight, then release the gate so the
    // first fails and rolls back. The queued switch must only start
    // afterwards and apply cleanly.
    final gate = Completer<void>();
    srs.gate = gate;
    srs.failFor = 'fr';
    final first = provider.setScope(const BuiltinCourseScope('fr'));
    while (!srs.hitGate) {
      await Future<void>.delayed(Duration.zero);
    }
    final second = provider.setScope(const BuiltinCourseScope('fr'));
    gate.complete();

    await expectLater(first, throwsA(isA<CourseScopeSwitchException>()));
    // Only after the failed switch (and its rollback) fully finished may
    // the failure clear — and the queued switch applies cleanly.
    srs.failFor = null;
    await second;

    expect(provider.scope, const BuiltinCourseScope('fr'));
    expect(LanguageContentStore.activeCode, 'fr');
    expect(await persistedScopeWire(), 'course-scope:v1:builtin:fr');
    expect(srs.calls.last, 'fr');
  });

  test('restart after a rolled-back switch restores the old language',
      () async {
    srs.failFor = 'fr';
    await expectLater(
      provider.setScope(const BuiltinCourseScope('fr')),
      throwsA(isA<CourseScopeSwitchException>()),
    );

    // A fresh provider (boot path) must restore the rolled-back choice.
    final rebooted = CourseProvider(prefs);
    await rebooted.load();
    expect(rebooted.scope, const BuiltinCourseScope('tr'));
  });
}
