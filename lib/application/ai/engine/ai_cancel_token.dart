// Dart imports:
import 'dart:async';

/// Cooperative cancellation handle for an in-flight AI request.
///
/// Mirrors the `cancel_check` callable polled between SSE lines in
/// `tool/gui/src/backend/ai_stream.py:iter_sse` and `ai/client.py:request_chat`.
/// The Dart side wraps the same idea in a token object: the engine polls
/// [isCanceled] between streamed lines and aborts the underlying `http` request
/// when it flips true.
///
/// This is a lower-level signal than the `_generation` counter on
/// `AiHintProvider` (which discards stale *results*); [AiCancelToken] stops the
/// *network* work itself.
class AiCancelToken {
  final _completer = Completer<void>();

  bool _canceled = false;

  /// `true` once [cancel] has been called.
  bool get isCanceled => _canceled;

  /// A future that completes when [cancel] is called. Convenient for callers
  /// that want to `await` cancellation alongside other futures.
  Future<void> get onCanceled => _completer.future;

  /// Flip the token to canceled. Safe to call multiple times - only the first
  /// call completes the internal future.
  void cancel() {
    if (_canceled) return;
    _canceled = true;
    _completer.complete();
  }
}

/// Exception raised by the engine when a request is aborted via [AiCancelToken].
///
/// Mirrors `tool/gui/src/backend/ai/config.py:AiCancelled`. Kept as a distinct
/// type so callers can distinguish a user-initiated cancel from a network error
/// and restore their UI to idle instead of showing an error banner.
class AiCancelled implements Exception {
  const AiCancelled([this.message]);

  final String? message;

  @override
  String toString() => message ?? 'AI request cancelled.';
}
