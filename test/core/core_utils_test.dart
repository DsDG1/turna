// Consolidated tests for core utility functions (Result, enumByName).

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/result.dart';
import 'package:turna/core/utils.dart';

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

  group('Result.guard', () {
    test('a successful async action yields Success with the value', () async {
      final result = await Result.guard(() async => 42);
      expect(result, isA<Success<int>>());
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.error, isNull);
    });

    test('a throwing async action yields Failure with the error', () async {
      final result = await Result.guard(() async => throw StateError('boom'));
      expect(result, isA<Failure<int>>());
      expect(result.isFailure, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.error, isA<StateError>());
    });

    test('guard never throws even when the action throws synchronously',
        () async {
      final result = await Result.guard<int>(
        () async {
          throw ArgumentError('sync');
        },
      );
      expect(result.isFailure, isTrue);
    });
  });
}
