import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:turna/application/ai/ai_grounded_resource_provider.dart';
import 'package:turna/application/ai/ai_lesson_helper_provider.dart';
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';

void main() {
  test('apply undo hands back the lesson captured before the write', () {
    final helper = AiLessonHelperProvider.withEngine(
      AiEngine(
        AiHttpClient.withClient(http.Client()),
        AiCache.forTest(maxEntries: 0, enabled: false),
      ),
      groundedProvider: AiGroundedResourceProvider.detached(),
    );
    const original = Lesson(
      id: 'lesson-1',
      name: 'Before',
      content: LessonContent(),
    );
    const rewritten = Lesson(
      id: 'lesson-1',
      name: 'After',
      content: LessonContent(),
    );

    helper.armApplyUndo(original);
    expect(helper.pendingUndoLesson?.name, 'Before');
    expect(helper.takeApplyUndo(), original);
    expect(helper.takeApplyUndo(), isNull);
    expect(rewritten.name, 'After');
  });

  test('queued lesson reloads finish in order', () async {
    final helper = AiLessonHelperProvider.withEngine(
      AiEngine(
        AiHttpClient.withClient(http.Client()),
        AiCache.forTest(maxEntries: 0, enabled: false),
      ),
      groundedProvider: AiGroundedResourceProvider.detached(),
    );
    final firstGate = Completer<void>();
    final order = <int>[];
    final first = helper.enqueueLessonReload(() async {
      await firstGate.future;
      order.add(1);
    });
    final second = helper.enqueueLessonReload(() async {
      order.add(2);
    });
    await Future<void>.delayed(Duration.zero);
    expect(order, isEmpty);
    firstGate.complete();
    await Future.wait([first, second]);
    expect(order, [1, 2]);
  });
}
