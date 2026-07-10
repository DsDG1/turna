// Flutter imports:
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_tts/flutter_tts.dart';

// Project imports:
import 'package:words625/application/course_provider.dart';
import 'package:words625/core/logger.dart';
import 'package:words625/di/injection.dart';
import 'package:words625/routing/routing.dart';
import 'package:words625/service/locator.dart';
import 'package:words625/views/app.dart';

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

  runApp(const Words625App());

  if (!kIsWeb) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await getIt<FlutterTts>().isLanguageAvailable("sw");
    });
  }
}