// LearningStats caches futures so a parent rebuild (e.g. tab switch) does not
// re-issue repository reads until StudyStatsProvider notifies.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:varnamala/application/study_stats_provider.dart';
import 'package:varnamala/domain/study/daily_stats.dart';
import 'package:varnamala/views/profile/widgets/learning_stats.dart';

import '../helpers/fake_study_stats.dart';

class _CountingStudyStats extends FakeStudyStatsProvider {
  int todayCalls = 0;
  int weekCalls = 0;
  int minutesCalls = 0;
  int accuracyCalls = 0;
  int lessonsCalls = 0;
  int reviewsCalls = 0;

  @override
  Future<DailyStudyStats> getTodayStats() async {
    todayCalls++;
    return DailyStudyStats(date: DateTime(2026, 7, 11), totalXp: 10);
  }

  @override
  Future<List<DailyStudyStats>> getLastNDays(int n) async {
    weekCalls++;
    return List.generate(
      n,
      (i) => DailyStudyStats(date: DateTime(2026, 7, 11 - i), totalXp: i),
    );
  }

  @override
  Future<int> getTotalStudyMinutes() async {
    minutesCalls++;
    return 5;
  }

  @override
  Future<double> getOverallAccuracy() async {
    accuracyCalls++;
    return 0.5;
  }

  @override
  Future<int> getTotalRecordedLessons() async {
    lessonsCalls++;
    return 1;
  }

  @override
  Future<int> getTotalRecordedReviews() async {
    reviewsCalls++;
    return 2;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rebuild without notifyListeners does not re-fetch stats',
      (tester) async {
    final fake = _CountingStudyStats();
    final rebuild = ValueNotifier<int>(0);

    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<StudyStatsProvider>.value(
            value: fake,
            child: ValueListenableBuilder<int>(
              valueListenable: rebuild,
              builder: (_, __, ___) => const SingleChildScrollView(
                child: LearningStats(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fake.todayCalls, 1);
    expect(fake.weekCalls, 1);
    expect(fake.minutesCalls, 1);

    // Parent rebuild (simulates tab re-entry without provider change).
    // LearningStats State is preserved under the same parent Element tree
    // only if LearningStats itself is not recreated with a new State —
    // ValueListenableBuilder rebuilds child, which creates a new
    // LearningStats Element... actually const LearningStats keeps State
    // if the Element is updated in place.
    rebuild.value++;
    await tester.pumpAndSettle();

    // Futures were cached on the State; didChangeDependencies does not
    // re-attach because provider identity is unchanged.
    expect(fake.todayCalls, 1);
    expect(fake.weekCalls, 1);
    expect(fake.minutesCalls, 1);

    // Provider notify → refresh futures once more.
    fake.notifyListeners();
    await tester.pumpAndSettle();

    expect(fake.todayCalls, 2);
    expect(fake.weekCalls, 2);
    expect(fake.minutesCalls, 2);
  });
}
