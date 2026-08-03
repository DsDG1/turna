import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/core/enums.dart';
import 'package:turna/service/locator.dart';

class _FakeAppPrefs implements AppPrefs {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('LanguageProvider', () {
    test('ttsLanguageCode returns tr for Turkish', () {
      final provider = LanguageProvider(_FakeAppPrefs());
      provider.selectedLanguage = TargetLanguage.turkish;
      expect(provider.ttsLanguageCode, 'tr');
    });
  });
}
