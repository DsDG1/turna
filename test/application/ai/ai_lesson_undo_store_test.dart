import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/ai/ai_lesson_undo_store.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saves one lesson snapshot and take clears it', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    final store = AiLessonUndoStore(prefs: AppPrefs(preferences));
    const original = Lesson(
      id: 'lesson-1',
      name: 'Before',
      content: LessonContent(),
    );

    await store.save(original);
    expect(store.peek()?.name, 'Before');
    expect(store.peek()?.id, 'lesson-1');

    final taken = await store.take();
    expect(taken?.name, 'Before');
    expect(store.peek(), isNull);
  });

  test('corrupt snapshot is ignored', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    await preferences.setString(kAiLessonUndoKey, '{not json');
    final store = AiLessonUndoStore(prefs: AppPrefs(preferences));
    expect(store.peek(), isNull);
  });
}
