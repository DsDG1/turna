// Gate tests for the opt-in read-aloud master switch: auto-read must never
// fire while the switch is off, even when a course opts in per-course.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/smart_speech.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late SettingsProvider settings;

  setUp(() async {
    getIt.reset();
    SharedPreferences.setMockInitialValues({});
    final streaming = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(streaming);
    settings = SettingsProvider(prefs);
    getIt.registerSingleton<SettingsProvider>(settings);
    getIt.registerSingleton<CourseProvider>(CourseProvider());
  });

  tearDown(getIt.reset);

  test('per-course opt-in alone does not auto-read while the gate is off',
      () async {
    final scope = getIt<CourseProvider>().courseScope;
    await settings.setAutoReadOnTapFor(scope, true);

    expect(settings.ttsFeatureEnabled, isFalse);
    expect(autoReadOnTapForActiveCourse(), isFalse);
  });

  test('enabling the gate lets the per-course setting take over', () async {
    final scope = getIt<CourseProvider>().courseScope;
    await settings.setAutoReadOnTapFor(scope, true);
    await settings.setTtsFeatureEnabled(true);

    expect(autoReadOnTapForActiveCourse(), isTrue);

    await settings.setAutoReadOnTapFor(scope, false);
    expect(autoReadOnTapForActiveCourse(), isFalse);
  });
}
