import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/core/enums.dart';
import 'package:varnamala/service/locator.dart';

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
