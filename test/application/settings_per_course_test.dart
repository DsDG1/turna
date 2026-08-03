import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    settings = SettingsProvider(prefs);
  });

  group('per-course auto-read-on-tap', () {
    test('defaults to true for any scope', () {
      expect(settings.autoReadOnTapFor(''), isTrue);
      expect(settings.autoReadOnTapFor('anki:abc123'), isTrue);
    });

    test('set + persist, isolated per scope', () async {
      await settings.setAutoReadOnTapFor('', false);
      await settings.setAutoReadOnTapFor('anki:abc123', false);
      await settings.setAutoReadOnTapFor('anki:def456', true);

      final reloaded = SettingsProvider(prefs);
      expect(reloaded.autoReadOnTapFor(''), isFalse);
      expect(reloaded.autoReadOnTapFor('anki:abc123'), isFalse);
      expect(reloaded.autoReadOnTapFor('anki:def456'), isTrue);
      // An unconfigured scope still defaults to true.
      expect(reloaded.autoReadOnTapFor('anki:untouched'), isTrue);
    });

    test('uses distinct pref keys per scope', () async {
      await settings.setAutoReadOnTapFor('anki:abc123', false);
      // A different scope is unaffected.
      expect(settings.autoReadOnTapFor('anki:def456'), isTrue);
    });
  });

  group('per-course native language', () {
    test('defaults to en for any scope', () {
      expect(settings.nativeLanguageCodeFor(''), 'en');
      expect(settings.nativeLanguageCodeFor('anki:abc123'), 'en');
    });

    test('set + persist, isolated per scope', () async {
      await settings.setNativeLanguageCodeFor('', 'zh');
      await settings.setNativeLanguageCodeFor('anki:abc123', 'ru');

      final reloaded = SettingsProvider(prefs);
      expect(reloaded.nativeLanguageCodeFor(''), 'zh');
      expect(reloaded.nativeLanguageCodeFor('anki:abc123'), 'ru');
      // An unconfigured scope still defaults to en.
      expect(reloaded.nativeLanguageCodeFor('anki:untouched'), 'en');
    });
  });
}
