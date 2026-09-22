import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/course_provider.dart';

void main() {
  test('boot failure is visible and can be cleared for retry', () {
    final course = CourseProvider();
    var notifications = 0;
    course.addListener(() => notifications++);

    expect(course.bootFailed, isFalse);
    course.reportBootFailure();
    expect(course.bootFailed, isTrue);
    course.reportBootFailure();
    course.clearBootFailure();
    expect(course.bootFailed, isFalse);
    expect(notifications, 2);
  });
}
