// Project imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/core/utils.dart';

enum _Fruit { apple, banana, cherry }

void main() {
  group('enumByName', () {
    test('resolves a known name', () {
      expect(
        enumByName(_Fruit.values, 'banana', fallback: _Fruit.apple),
        _Fruit.banana,
      );
    });

    test('falls back for an unknown name', () {
      expect(
        enumByName(_Fruit.values, 'durian', fallback: _Fruit.cherry),
        _Fruit.cherry,
      );
    });

    test('falls back for an empty name', () {
      expect(
        enumByName(_Fruit.values, '', fallback: _Fruit.apple),
        _Fruit.apple,
      );
    });
  });
}