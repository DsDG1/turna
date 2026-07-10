// Flutter imports:
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/core/logger.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/routing/routing.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/service/piper_swahili_tts.dart';
import 'package:varnamala/service/tts_availability_checker.dart';
import 'package:varnamala/views/app.dart';

/// Install global error handlers so uncaught framework and platform errors
/// are observable in the app log instead of disappearing. This is an offline
/// app, so errors are logged locally only — never sent to a remote backend.
void _installGlobalErrorHandlers() {
  // Framework errors that the Flutter framework would otherwise print to
  // the console in debug and swallow in release.
  FlutterError.onError = (FlutterErrorDetails details) {
    logger.e('Uncaught framework error', error: details.exception,
        stackTrace: details.stack);
    FlutterError.presentError(details);
  };

  // Errors thrown outside the Flutter framework (isolates, async gaps).
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logger.e('Uncaught platform error', error: error, stackTrace: stack);
    return true; // handled: suppress the default crash print.
  };
}

Future<void> main() async {
  // Capture errors as early as possible, before any binding work runs.
  _installGlobalErrorHandlers();

  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();
  getIt.registerLazySingleton<AppRouter>(() => AppRouter());

  // AppPrefs (and other async-native services) must be registered before the
  // first frame because MultiProvider creates ThemeProvider immediately.
  await setupLocator();

  // Kick off the course load on the first frame instead of blocking before
  // runApp. CourseTree renders its own loading indicator until the shells
  // arrive, so the app paints immediately rather than showing a blank screen
  // during the (cold) DB read. CourseProvider.load() is idempotent, so the
  // CourseTree's defensive ensureSectionLoaded can never double-load or reset
  // shells back to their initial state.
  runApp(const VarnamalaApp());

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await getIt<CourseProvider>().load();

    if (!kIsWeb) {
      // Prefer Google TTS on Android before any speak/availability checks so
      // OEM default engines without Swahili do not shadow the real system
      // voice.
      await getIt<TtsAvailabilityChecker>().configureSystemEngine();

      // Warm the Piper offline worker in the background so the first
      // tap-to-speak (when falling back to / preferring the bundled model)
      // does not stall on model load. Fire-and-forget: it runs in its own
      // isolate and never blocks the UI.
      getIt<PiperSwahiliTts>().prewarm().catchError((_) {/* best-effort */});
    }
  });
}