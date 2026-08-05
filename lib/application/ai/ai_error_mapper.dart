// Dart imports:
import 'dart:async';
import 'dart:io';

// Project imports:
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
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
    if (error is TimeoutException) {
      return AiErrorMapping(
        kind: AiErrorKind.timeout,
        message: AppStrings.aiErrorTimeout,
      );
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
    if (_looksAuth(lower) || text.contains('HTTP 401') || text.contains('HTTP 403')) {
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
      case AiErrorKind.unknown:
        return AppStrings.aiErrorUnknown;
    }
  }

  static bool _looksIncomplete(String lower) =>
      lower.contains('config incomplete') ||
      lower.contains('api key') && lower.contains('incomplete') ||
      lower.contains('please fill in') ||
      lower.contains('not configured');

  static bool _looksAuth(String lower) =>
      lower.contains('unauthorized') ||
      lower.contains('invalid api key') ||
      lower.contains('authentication') ||
      lower.contains('forbidden') ||
      lower.contains('invalid_api_key');
}
