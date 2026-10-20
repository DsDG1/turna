// Dart imports:
import 'dart:async';
import 'dart:io';

// Project imports:
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/l10n/app_strings.dart';

/// Kind of AI failure exposed to UI (no raw exception strings).
enum AiErrorKind {
  notConfigured,
  network,
  timeout,
  unauthorized,
  rateLimited,
  cancelled,
  parseFailed,

  /// The endpoint refused the model id we sent (`unknown model` family — MiniMax
  /// answers `invalid params, unknown model '' (2013)`). Retrying cannot fix it:
  /// the id has to be corrected in Settings.
  modelUnavailable,

  /// The configured endpoint answered 3xx. The request — and its
  /// `Authorization: Bearer` header — was not followed, so the user has to
  /// point the base URL at the final endpoint themselves.
  endpointRedirect,

  /// The reply hit the output-token ceiling (`finish_reason: length`) and the
  /// payload was cut mid-way. Retrying reproduces it exactly; the request has
  /// to ask for less content instead.
  truncated,

  unknown,
}

/// Result of mapping an [Object] thrown by engine/providers into user-facing
/// copy. Pure function surface — easy to unit-test without network.
class AiErrorMapping {
  const AiErrorMapping({
    required this.kind,
    required this.message,
    this.canRetry = true,
    this.canConfigure = false,
  });

  factory AiErrorMapping.message(
    String message, {
    AiErrorKind kind = AiErrorKind.unknown,
    bool canRetry = true,
    bool canConfigure = false,
  }) =>
      AiErrorMapping(
        kind: kind,
        message: message,
        canRetry: canRetry,
        canConfigure: canConfigure,
      );

  final AiErrorKind kind;
  final String message;
  final bool canRetry;
  final bool canConfigure;
}

/// Central mapper from exceptions / status strings to [AiErrorMapping].
///
/// Providers catch, map, and store [AiErrorMapping.message] (never
/// `e.toString()`) so the UI never leaks stack traces or HTTP bodies.
class AiErrorMapper {
  const AiErrorMapper._();

  /// Map [error] (and optional [fallbackKind]) to a user-facing mapping.
  static AiErrorMapping map(Object error, {AiErrorKind? fallbackKind}) {
    if (error is AiCancelled) {
      return AiErrorMapping(
        kind: AiErrorKind.cancelled,
        message: AppStrings.aiErrorCancelled,
        canRetry: false,
      );
    }
    if (error is AiRedirectNotFollowed) {
      // Fixed copy on purpose: the redirect's own response body is never
      // surfaced, so there is nothing here to interpolate even if the
      // destination had echoed something back.
      return AiErrorMapping(
        kind: AiErrorKind.endpointRedirect,
        message: AppStrings.aiErrorEndpointRedirect,
        canRetry: false,
        canConfigure: true,
      );
    }
    if (error is TimeoutException) {
      return AiErrorMapping(
        kind: AiErrorKind.timeout,
        message: AppStrings.aiErrorTimeout,
      );
    }
    if (error is AiHttpError) {
      // Status-code first: the body text is for humans, and matching on it was
      // how a 400 containing the word "json" used to be reported as a parse
      // failure.
      return _fromStatus(error.statusCode, error.detail);
    }
    if (error is SocketException || error is HttpException) {
      return AiErrorMapping(
        kind: AiErrorKind.network,
        message: AppStrings.aiErrorNetwork,
      );
    }

    final text = error.toString();
    final lower = text.toLowerCase();

    if (_looksIncomplete(lower)) {
      return AiErrorMapping(
        kind: AiErrorKind.notConfigured,
        message: AppStrings.aiErrorNotConfigured,
        canRetry: false,
        canConfigure: true,
      );
    }
    if (_looksTruncated(lower)) {
      return AiErrorMapping(
        kind: AiErrorKind.truncated,
        message: AppStrings.aiErrorTruncated,
        canRetry: false,
      );
    }
    if (_looksModelUnavailable(lower)) {
      return AiErrorMapping(
        kind: AiErrorKind.modelUnavailable,
        message: AppStrings.aiErrorModelUnavailable,
        canRetry: false,
        canConfigure: true,
      );
    }
    if (_looksAuth(lower) ||
        text.contains('HTTP 401') ||
        text.contains('HTTP 403')) {
      return AiErrorMapping(
        kind: AiErrorKind.unauthorized,
        message: AppStrings.aiErrorUnauthorized,
        canRetry: false,
        canConfigure: true,
      );
    }
    if (text.contains('HTTP 429') ||
        lower.contains('rate limit') ||
        lower.contains('quota') ||
        lower.contains('额度')) {
      return AiErrorMapping(
        kind: AiErrorKind.rateLimited,
        message: AppStrings.aiErrorRateLimited,
      );
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return AiErrorMapping(
        kind: AiErrorKind.timeout,
        message: AppStrings.aiErrorTimeout,
      );
    }
    if (lower.contains('socket') ||
        lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused')) {
      return AiErrorMapping(
        kind: AiErrorKind.network,
        message: AppStrings.aiErrorNetwork,
      );
    }
    if (error is FormatException ||
        lower.contains('format exception') ||
        lower.contains('could not parse') ||
        lower.contains('json')) {
      return AiErrorMapping(
        kind: AiErrorKind.parseFailed,
        message: AppStrings.aiErrorParseFailed,
      );
    }

    final kind = fallbackKind ?? AiErrorKind.unknown;
    return AiErrorMapping(
      kind: kind,
      message: _messageForKind(kind),
    );
  }

  static String _messageForKind(AiErrorKind kind) {
    switch (kind) {
      case AiErrorKind.notConfigured:
        return AppStrings.aiErrorNotConfigured;
      case AiErrorKind.network:
        return AppStrings.aiErrorNetwork;
      case AiErrorKind.timeout:
        return AppStrings.aiErrorTimeout;
      case AiErrorKind.unauthorized:
        return AppStrings.aiErrorUnauthorized;
      case AiErrorKind.rateLimited:
        return AppStrings.aiErrorRateLimited;
      case AiErrorKind.cancelled:
        return AppStrings.aiErrorCancelled;
      case AiErrorKind.parseFailed:
        return AppStrings.aiErrorParseFailed;
      case AiErrorKind.modelUnavailable:
        return AppStrings.aiErrorModelUnavailable;
      case AiErrorKind.endpointRedirect:
        return AppStrings.aiErrorEndpointRedirect;
      case AiErrorKind.truncated:
        return AppStrings.aiErrorTruncated;
      case AiErrorKind.unknown:
        return AppStrings.aiErrorUnknown;
    }
  }

  /// Classify a structured [AiHttpError] by status code.
  ///
  /// [detail] is only consulted for the two cases the status code cannot
  /// disambiguate: a 400 that means "no such model" versus one that means
  /// "your parameters are wrong".
  static AiErrorMapping _fromStatus(int status, String detail) {
    final lower = detail.toLowerCase();
    if (status == 401 || status == 403) {
      return AiErrorMapping(
        kind: AiErrorKind.unauthorized,
        message: AppStrings.aiErrorUnauthorized,
        canRetry: false,
        canConfigure: true,
      );
    }
    if (status == 429) {
      return AiErrorMapping(
        kind: AiErrorKind.rateLimited,
        message: AppStrings.aiErrorRateLimited,
      );
    }
    if (status == 408 || status == 504) {
      return AiErrorMapping(
        kind: AiErrorKind.timeout,
        message: AppStrings.aiErrorTimeout,
      );
    }
    if (status == 400 || status == 422) {
      if (_looksModelUnavailable(lower)) {
        return AiErrorMapping(
          kind: AiErrorKind.modelUnavailable,
          message: AppStrings.aiErrorModelUnavailable,
          canRetry: false,
          canConfigure: true,
        );
      }
      // A bad-request is a caller-side problem: repeating it changes nothing.
      return AiErrorMapping(
        kind: AiErrorKind.unknown,
        message: AppStrings.aiErrorUnknown,
        canRetry: false,
      );
    }
    if (status >= 500 && status <= 599) {
      return AiErrorMapping(
        kind: AiErrorKind.network,
        message: AppStrings.aiErrorNetwork,
      );
    }
    return AiErrorMapping(
      kind: AiErrorKind.unknown,
      message: AppStrings.aiErrorUnknown,
      canRetry: false,
    );
  }

  /// Did the model get cut off by the output-token ceiling?
  ///
  /// Matched on the copy the generators raise, not on provider text: a
  /// `finish_reason: length` reply is detected in the engine, which then throws
  /// with this wording. Catching it before the generic "looks like JSON"
  /// branch matters — a truncated payload also fails to parse, and "格式异常"
  /// would send the user to retry an impossible request.
  static bool _looksTruncated(String lower) =>
      lower.contains('truncated') ||
      lower.contains('finish_reason: length') ||
      lower.contains('length limit') ||
      lower.contains('截断');


  static bool _looksIncomplete(String lower) =>
      lower.contains('config incomplete') ||
      lower.contains('api key') && lower.contains('incomplete') ||
      lower.contains('please fill in') ||
      lower.contains('not configured');

  /// Does this error mean the endpoint rejected the model id?
  ///
  /// Deliberately narrow: only the phrases providers use for "there is no such
  /// model" (MiniMax `invalid params, unknown model '' (2013)`, OpenAI
  /// `model_not_found`, generic `no such model`). A bare `400` must not be
  /// swallowed here — most 400s mean something else.
  static bool _looksModelUnavailable(String lower) =>
      lower.contains('unknown model') ||
      lower.contains('model_not_found') ||
      lower.contains('model not found') ||
      lower.contains('no such model') ||
      lower.contains('invalid model') ||
      (lower.contains('does not exist') && lower.contains('model'));

  static bool _looksAuth(String lower) =>
      lower.contains('unauthorized') ||
      lower.contains('invalid api key') ||
      lower.contains('authentication') ||
      lower.contains('forbidden') ||
      lower.contains('invalid_api_key');
}
