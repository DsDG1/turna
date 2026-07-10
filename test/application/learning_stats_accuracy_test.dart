// Regression: the "Overall Accuracy" stat on the profile page must convert
// the 0..1 fraction into a 0..100 percentage. The previous implementation
// had an operator-precedence bug (`?? 0.0 * 100` parses as `?? (0.0 * 100)`)
// which made the percentage always 0%.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:varnamala/application/study_stats_provider.dart';
import 'package:varnamala/views/profile/widgets/learning_stats.dart';

import '../helpers/fake_study_stats.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpOverallGrid(WidgetTester tester, double accuracy) async {
    final fake = _FakeStudyStats(accuracy: accuracy);

    // Setting the surface size avoids the layout overflow that would
    // otherwise interrupt smaller test viewports.
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<StudyStatsProvider>.value(
            value: fake,
            child: const SingleChildScrollView(
              child: LearningStats(),
            ),
          ),
        ),
      ),
    );
    // Pump until all 3 FutureBuilders resolve.
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
  }

  testWidgets('accuracy 0.75 is rendered as "75%"', (tester) async {
    await pumpOverallGrid(tester, 0.75);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('Overall Accuracy'), findsOneWidget);
  });

  testWidgets('accuracy 0.0 is rendered as "0%"', (tester) async {
    await pumpOverallGrid(tester, 0.0);
    expect(find.text('Overall Accuracy'), findsOneWidget);
  });

  testWidgets('accuracy 1.0 is rendered as "100%"', (tester) async {
    await pumpOverallGrid(tester, 1.0);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('accuracy 0.5 is rendered as "50%"', (tester) async {
    await pumpOverallGrid(tester, 0.5);
    expect(find.text('50%'), findsOneWidget);
  });
}

class _FakeStudyStats extends FakeStudyStatsProvider {
  _FakeStudyStats({required this.accuracy});

  final double accuracy;

  @override
  Future<double> getOverallAccuracy() async => accuracy;
}
