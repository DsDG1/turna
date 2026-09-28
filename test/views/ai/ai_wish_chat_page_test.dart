import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/ai/ai_course_provider.dart';
import 'package:turna/application/ai/ai_grounded_resource_provider.dart';
import 'package:turna/application/ai/ai_wish_provider.dart';
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/ai_wish_chat_page.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    ensurePathProviderMockForTest();
    ensureSqliteLibForTestHost();
    if (!getIt.isRegistered<ICourseRepository>()) {
      final db = emptyInMemoryCourseDatabase();
      getIt.registerSingleton<ICourseRepository>(CourseRepository(db));
    }
  });

  testWidgets(
      'AiWishChatPage mounts the authoring tombstone with a '
      'disabled open-GUI button when unconfigured', (tester) async {
    final engine = AiEngine(
      AiHttpClient.withClient(
          MockClient((_) async => throw UnimplementedError())),
      AiCache.forTest(),
    );
    final grounded = AiGroundedResourceProvider();
    final wishProvider =
        AiWishProvider.withEngine(engine, groundedProvider: grounded);
    final courseProvider =
        AiCourseProvider.withEngine(engine, groundedProvider: grounded);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AiWishProvider>.value(value: wishProvider),
          ChangeNotifierProvider<AiCourseProvider>.value(value: courseProvider),
          ChangeNotifierProvider<AiEngineConfigHolder>(
              create: (_) => AiEngineConfigHolder()),
        ],
        child: const MaterialApp(
          home: AiWishChatPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.settingsDesignCourseAiTitle), findsOneWidget);
    expect(find.text(AppStrings.authoringMovedTitle), findsOneWidget);
    expect(find.text(AppStrings.authoringMovedBody), findsOneWidget);
    expect(find.text(AppStrings.authoringMovedGuiUnconfigured), findsOneWidget);
    // GUI address is unconfigured in the test host, so the open button must
    // be disabled rather than constructing a speculative link.
    final openButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, AppStrings.authoringMovedOpenGui),
    );
    expect(openButton.onPressed, isNull);

    // Trigger pointer events (mouse hover, mouse move, pointer down, up)
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(const Offset(100, 100));
    await gesture.down(const Offset(100, 100));
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
