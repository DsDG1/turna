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

  // Eagerly kick off the course load so CourseTree (and any other consumer)
  // never has to trigger the load itself from a widget lifecycle method.
  // Doing it here means a tab round-trip can't reset the provider's cached
  // bodies back to shells (the previous incarnation of `CourseTree.initState`
  // did exactly that and produced a blank Course Tree after switching tabs).
  await getIt<CourseProvider>().load();

  runApp(const VarnamalaApp());

  if (!kIsWeb) {
    // Prefer Google TTS on Android before any speak/availability checks so
    // OEM default engines without Swahili do not shadow the real system voice.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await getIt<TtsAvailabilityChecker>().configureSystemEngine();
    });
  }
}