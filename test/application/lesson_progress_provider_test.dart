import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/lesson_progress_provider.dart';
import 'package:varnamala/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late LessonProgressProvider progress;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.preferences
        .setStringList(LocalStateKeys.completedLessonIds, const []);
    await prefs.preferences
        .setStringList(LocalStateKeys.perfectLessonIds, const []);
    progress = LessonProgressProvider(prefs);
  });

  test('recordLessonCompletion marks completed and perfect', () async {
    await progress.recordLessonCompletion(lessonId: 'l-1', wasPerfect: true);
    expect(progress.isLessonCompleted('l-1'), isTrue);
    expect(progress.isLessonPerfect('l-1'), isTrue);
  });

  test('resetLessonProgress clears sets', () async {
    await progress.recordLessonCompletion(lessonId: 'l-1', wasPerfect: true);
    await progress.resetLessonProgress();
    expect(progress.completedLessonIds, isEmpty);
    expect(progress.perfectLessonIds, isEmpty);
  });

  test('completedLessonsStream yields after completion', () async {
    final events = <Set<String>>[];
    final sub = progress.completedLessonsStream.listen(events.add);
    // Drain the initial yield from async*.
    await Future<void>.delayed(Duration.zero);
    await progress.recordLessonCompletion(lessonId: 'l-2', wasPerfect: false);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(events.any((s) => s.contains('l-2')), isTrue);
  });
}
