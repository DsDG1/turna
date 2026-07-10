// Unit tests for the Result discriminated-result type.

import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/core/result.dart';

void main() {
  group('guard', () {
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

  group('guardSync', () {
    test('wraps a synchronous value', () {
      final result = Result.guardSync(() => 'hi');
      expect(result.valueOrNull, 'hi');
      expect(result.isSuccess, isTrue);
    });

    test('captures a synchronous throw', () {
      final result = Result.guardSync(() => throw const FormatException('x'));
      expect(result.isFailure, isTrue);
      expect(result.error, isA<FormatException>());
    });
  });

  group('map / flatMap', () {
    test('map transforms a success value', () {
      final result = Result.guardSync(() => 2).map((v) => v * 3);
      expect(result.valueOrNull, 6);
    });

    test('map propagates a failure untouched', () {
      final result = Result.guardSync(() => throw Exception('no')).map((v) => v);
      expect(result.isFailure, isTrue);
    });

    test('flatMap chains a success into another result', () {
      final result = Result.guardSync(() => 2).flatMap((v) => Success(v + 1));
      expect(result.valueOrNull, 3);
    });

    test('flatMap propagates a failure untouched', () {
      final result =
          Result.guardSync(() => throw Exception('no')).flatMap((v) => Success(v));
      expect(result.isFailure, isTrue);
    });
  });

  group('fold', () {
    test('invokes onSuccess for a success', () {
      final value = Result.guardSync(() => 10).fold(
        onSuccess: (v) => 'ok:$v',
        onFailure: (_) => 'err',
      );
      expect(value, 'ok:10');
    });

    test('invokes onFailure for a failure', () {
      final value = Result.guardSync(() => throw Exception()).fold(
        onSuccess: (v) => 'ok:$v',
        onFailure: (e) => 'err',
      );
      expect(value, 'err');
    });
  });

  test('logFailure is a no-op on success and returns this', () {
    final result = Result.guardSync(() => 5);
    expect(identical(result.logFailure('label'), result), isTrue);
  });

  test('logFailure returns this on failure without throwing', () {
    final result = Result.guardSync(() => throw Exception('x'));
    expect(identical(result.logFailure('label'), result), isTrue);
  });
}