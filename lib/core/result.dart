// Project imports:
import 'package:turna/core/logger.dart';

/// A lightweight discriminated result type for operations that can fail.
///
/// Prefer this over scattering `try/catch + debugPrint` across call sites:
/// it makes the failure channel explicit in the type signature and gives one
/// place to route errors through the [logger].
///
/// Example:
/// ```dart
/// final result = await Result.guard(() => awardXp());
/// if (result.isFailure) logger.w('XP award failed', error: result.error);
/// ```
sealed class Result<T> {
  const Result();

  /// Wraps a potentially-throwing async call into a [Result]. Any exception
  /// becomes a [Failure] carrying the error and stack trace; never throws.
  static Future<Result<T>> guard<T>(Future<T> Function() action) async {
    try {
      return Success(await action());
    } catch (e, st) {
      return Failure(e, st);
    }
  }

  /// Wraps a synchronous call. Use [guard] for async work.
  static Result<T> guardSync<T>(T Function() action) {
    try {
      return Success(action());
    } catch (e, st) {
      return Failure(e, st);
    }
  }

  /// `true` when the operation succeeded.
  bool get isSuccess => this is Success<T>;

  /// `true` when the operation failed.
  bool get isFailure => this is Failure<T>;

  /// The successful value, or `null` on failure. Prefer pattern matching
  /// (`switch`/`fold`) over this when the value must be used safely.
  T? get valueOrNull;

  /// The caught error, or `null` on success.
  Object? get error;

  /// Transform on success; propagate failures untouched.
  Result<R> map<R>(R Function(T value) transform);

  /// Flat-map on success; propagate failures untouched.
  Result<R> flatMap<R>(Result<R> Function(T value) transform);

  /// Run [onSuccess] or [onFailure] and return a value of either branch.
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Object? error) onFailure,
  });

  /// Log the failure through [logger] if this is a [Failure], tagged with
  /// [label] for context. Returns `this` for chaining.
  Result<T> logFailure(String label) {
    if (this is Failure<T>) {
      logger.w('$label: $error', error: error, stackTrace: stackTrace);
    }
    return this;
  }

  /// The failure stack trace, or `null` on success.
  StackTrace? get stackTrace;
}

/// A successful [Result] carrying [value].
final class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);

  @override
  T? get valueOrNull => value;

  @override
  Object? get error => null;

  @override
  StackTrace? get stackTrace => null;

  @override
  Result<R> map<R>(R Function(T value) transform) =>
      Result.guardSync(() => transform(value));

  @override
  Result<R> flatMap<R>(Result<R> Function(T value) transform) => transform(value);

  @override
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Object? error) onFailure,
  }) =>
      onSuccess(value);
}

/// A failed [Result] carrying the [error] and [stackTrace].
final class Failure<T> extends Result<T> {
  @override
  final Object? error;

  @override
  final StackTrace? stackTrace;

  const Failure(this.error, [this.stackTrace]);

  @override
  T? get valueOrNull => null;

  @override
  Result<R> map<R>(R Function(T value) transform) => Failure(error, stackTrace);

  @override
  Result<R> flatMap<R>(Result<R> Function(T value) transform) =>
      Failure(error, stackTrace);

  @override
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Object? error) onFailure,
  }) =>
      onFailure(error);
}