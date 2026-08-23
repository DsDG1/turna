/// Structured outcome of a settings operation performed by a command /
/// coordinator. Widgets never receive raw exception text — a failure carries
/// a stable [code] for tests and analytics plus a localized user message.
sealed class SettingsOperationResult {
  const SettingsOperationResult();
}

final class SettingsOperationSuccess extends SettingsOperationResult {
  const SettingsOperationSuccess({this.restartRequired = false});

  /// True when the operation only fully takes effect after an app restart
  /// (e.g. a database-level change). UI must only show a restart hint when
  /// this is set.
  final bool restartRequired;
}

final class SettingsOperationFailure extends SettingsOperationResult {
  const SettingsOperationFailure({
    required this.code,
    required this.userMessage,
    this.retryable = false,
  });

  /// Stable machine-readable code, e.g. `reminder.scheduleFailed`.
  final String code;

  /// User-presentable, secret-free message.
  final String userMessage;

  /// Whether re-running the same command plausibly helps.
  final bool retryable;
}
