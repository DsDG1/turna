// Flutter imports:
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/core/log_capture.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/system_health_monitor.dart';
import 'package:turna/service/app_startup.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/app.dart';

/// Install global error handlers so uncaught framework and platform errors
/// are observable in the app log instead of disappearing. This is an offline
/// app, so errors are logged locally only — never sent to a remote backend.
void _installGlobalErrorHandlers() {
  // Framework errors that the Flutter framework would otherwise print to
  // the console in debug and swallow in release.
  FlutterError.onError = (FlutterErrorDetails details) {
    logger.e('Uncaught framework error',
        error: details.exception, stackTrace: details.stack);
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

  // AppPrefs (and other async-native services) must be registered before the
  // first frame because MultiProvider creates ThemeProvider immediately.
  await setupLocator();

  // 透明度报告:挂上本地日志捕获,跨重启保留。
  // 必须在 configureDependencies 之后,这样 logger 已是单例;
  // 放在 runApp 之前,确保第一帧之前的早期日志也能进入。
  await LogCapture.instance.install();
  await getIt<SystemHealthMonitor>().install(LogCapture.instance.entries);

  // When companion explain prefs change (language/depth), drop engine cache so
  // stale replies in the wrong language are not replayed.
  AiExplainPrefsStore.onCacheInvalidate = () {
    try {
      getIt<AiEngine>().clearCache();
    } catch (_) {/* AiEngine may be unregistered — best-effort cache clear */}
  };

  // Lock the app to portrait unless the user has enabled auto-rotation in
  // Settings (default off). Applied before the first frame so the splash is
  // already portrait; the live toggle is handled by _OrientationController.
  await SystemChrome.setPreferredOrientations(
    getIt<SettingsProvider>().autoRotateEnabled
        ? []
        : [DeviceOrientation.portraitUp],
  );

  // Kick off the course load on the first frame instead of blocking before
  // runApp. CourseTree renders its own loading indicator until the shells
  // arrive, so the app paints immediately rather than showing a blank screen
  // during the (cold) DB read. CourseProvider.load() is idempotent, so the
  // CourseTree's defensive ensureSectionLoaded can never double-load or reset
  // shells back to their initial state.
  runApp(const TurnaApp());

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(continueTurnaStartup());
  });
}
