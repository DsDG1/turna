import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late AccessibilityProvider acc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    acc = AccessibilityProvider(prefs);
  });

  test('defaults are off, textScale 100%', () {
    expect(acc.textScale, 100);
    expect(acc.reducedMotion, isFalse);
    expect(acc.highContrast, isFalse);
    expect(acc.dyslexiaFont, isFalse);
    expect(acc.sensoryReduce, isFalse);
    expect(acc.focusMode, isFalse);
  });

  test('textScaler derives from textScale percent', () async {
    expect(acc.textScaler, const TextScaler.linear(1.0));
    await acc.setTextScale(150);
    expect(acc.textScaler, const TextScaler.linear(1.5));
  });

  test('setTextScale clamps to 100..200', () async {
    await acc.setTextScale(50);
    expect(acc.textScale, 100);
    await acc.setTextScale(300);
    expect(acc.textScale, 200);
  });

  test('flags persist and reload', () async {
    await acc.setReducedMotion(true);
    await acc.setHighContrast(true);
    await acc.setDyslexiaFont(true);
    await acc.setSensoryReduce(true);
    await acc.setFocusMode(true);
    await acc.setTextScale(200);

    final reloaded = AccessibilityProvider(prefs);
    expect(reloaded.reducedMotion, isTrue);
    expect(reloaded.highContrast, isTrue);
    expect(reloaded.dyslexiaFont, isTrue);
    expect(reloaded.sensoryReduce, isTrue);
    expect(reloaded.focusMode, isTrue);
    expect(reloaded.textScale, 200);
  });

  test('quietFeedback mirrors sensoryReduce', () async {
    await acc.setSensoryReduce(true);
    expect(acc.quietFeedback, isTrue);
    await acc.setSensoryReduce(false);
    expect(acc.quietFeedback, isFalse);
  });

  test('setters notify listeners', () async {
    int notifications = 0;
    acc.addListener(() => notifications++);

    await acc.setHighContrast(true);
    await acc.setTextScale(130);
    await acc.setFocusMode(true);

    // notifyListeners() fires synchronously inside each setter.
    expect(notifications, 3);
  });
}
