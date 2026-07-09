import 'package:flutter_test/flutter_test.dart';
import 'package:words625/application/language_provider.dart';
import 'package:words625/core/enums.dart';
import 'package:words625/service/locator.dart';

class _FakeAppPrefs implements AppPrefs {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('LanguageProvider', () {
    test('ttsLanguageCode returns sw for Swahili', () {
      final provider = LanguageProvider(_FakeAppPrefs());
      provider.selectedLanguage = TargetLanguage.swahili;
      expect(provider.ttsLanguageCode, 'sw');
    });
  });
}
