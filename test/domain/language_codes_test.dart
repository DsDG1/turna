// Unit tests for LanguageCodes.lookupFoldKey — the key fold applied on BOTH
// sides of the per-language term index (index build + dictionary lookups).
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/language_codes.dart';

void main() {
  group('lookupFoldKey', () {
    test('Turkish İ folds to i', () {
      expect(LanguageCodes.lookupFoldKey('İSTANBUL', 'tr'), 'istanbul');
      expect(LanguageCodes.lookupFoldKey('İyi', 'tr'), 'iyi');
    });

    test('Turkish ASCII I folds to dotless ı', () {
      expect(LanguageCodes.lookupFoldKey('IĞDIR', 'tr'), 'ığdır');
      // Stored content and typed query agree either way round.
      expect(
        LanguageCodes.lookupFoldKey('IŞIN', 'tr'),
        LanguageCodes.lookupFoldKey('ışın', 'tr'),
      );
    });

    test('non-Turkish languages use plain lowercase', () {
      expect(LanguageCodes.lookupFoldKey('Écouter', 'fr'), 'écouter');
      expect(LanguageCodes.lookupFoldKey('I', 'fr'), 'i');
    });

    test('İ folds to plain i in every language (no combining-dot keys)', () {
      // Plain toLowerCase() would produce 'i' + U+0307 here — a key no
      // typed query can ever match.
      expect(LanguageCodes.lookupFoldKey('İzmir', 'fr'), 'izmir');
      expect(LanguageCodes.lookupFoldKey('İzmir', 'de'), 'izmir');
      expect(
        LanguageCodes.lookupFoldKey('İzmir', 'az'),
        LanguageCodes.lookupFoldKey('izmir', 'az'),
      );
    });

    test('Azerbaijani shares the Turkish dotless-I rule', () {
      expect(LanguageCodes.lookupFoldKey('IRAQ', 'az'), 'ıraq');
      expect(
        LanguageCodes.lookupFoldKey('QIRIM', 'az'),
        LanguageCodes.lookupFoldKey('qırım', 'az'),
      );
      // Non-dotless languages keep ASCII I → i.
      expect(LanguageCodes.lookupFoldKey('IRAQ', 'en'), 'iraq');
    });

    test('trims whitespace', () {
      expect(LanguageCodes.lookupFoldKey('  Merhaba ', 'tr'), 'merhaba');
    });
  });
}
