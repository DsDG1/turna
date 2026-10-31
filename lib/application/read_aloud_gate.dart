// Project imports:
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';

/// Whether 跟读 (mic read-aloud) exercises run recognition, ADR 0061.
///
/// The opt-in master switch only — platform capability is a separate check
/// (`ReadAloudBackend.isSupported`) the renderer performs itself, so this
/// helper stays about user intent. Mirrors the defensive read in
/// `smart_speech.dart`: DI-unavailable environments (unit tests without the
/// provider graph) read as "off", and read-aloud cards degrade to
/// listen-only rather than throwing.
bool readAloudExercisesEnabled() {
  try {
    return getIt<SettingsProvider>().readAloudExercisesEnabled;
  } catch (_) {
    // GetIt optional-dependency guard: absence means the feature is off.
    return false;
  }
}
