import 'package:flutter_test/flutter_test.dart';
import 'package:turna/service/course_db_ready.dart';

void main() {
  test('ensure runs the body once and shares the future', () async {
    var calls = 0;
    final gate = CourseDbReadyGate(() async {
      calls++;
      await Future<void>.delayed(Duration.zero);
    });

    await Future.wait([gate.ensure(), gate.ensure()]);

    expect(calls, 1);
  });

  test('a failed ensure is not started again', () async {
    var calls = 0;
    final gate = CourseDbReadyGate(() async {
      calls++;
      throw StateError('seed failed');
    });

    await expectLater(gate.ensure(), throwsStateError);
    await expectLater(gate.ensure(), throwsStateError);
    expect(calls, 1);
  });
}
