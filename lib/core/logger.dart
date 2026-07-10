// Package imports:
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// App-wide logger.
///
/// In debug/test builds every log level is emitted. In release builds only
/// warnings and errors surface, so production logs are not flooded with
/// routine debug noise. This is an offline app — logs go to the console (and
/// the platform log) only, never to a remote backend.
final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 80,
    noBoxingByDefault: true,
  ),
  filter: _ReleaseAwareFilter(),
);

/// Emits all logs in debug/test; suppresses below `Level.warning` in release.
class _ReleaseAwareFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if (kReleaseMode) {
      return event.level.index >= Level.warning.index;
    }
    return true;
  }
}