// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_tts/flutter_tts.dart';

// Project imports:
import 'package:words625/di/injection.dart';
import 'package:words625/routing/routing.dart';
import 'package:words625/service/locator.dart';
import 'package:words625/views/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();
  getIt.registerLazySingleton<AppRouter>(() => AppRouter());

  // AppPrefs (and other async-native services) must be registered before the
  // first frame because MultiProvider creates ThemeProvider immediately.
  await setupLocator();

  runApp(const Words625App());

  if (!kIsWeb) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await getIt<FlutterTts>().isLanguageAvailable("sw");
    });
  }
}