// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/providers.dart';
import 'package:varnamala/application/theme_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/routing/routing.dart';
import 'package:varnamala/views/theme.dart';

final router = getIt<AppRouter>();

class VarnamalaApp extends StatelessWidget {
  const VarnamalaApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: providers,
      child: Selector<ThemeProvider, ThemeMode>(
        selector: (_, themeProvider) => themeProvider.themeMode,
        builder: (context, themeMode, _) {
          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            title: 'Varnamala',
            theme: VarnamalaTheme.lightTheme,
            darkTheme: VarnamalaTheme.darkTheme,
            themeMode: themeMode,
            routerConfig: router.config(),
          );
        },
      ),
    );
  }
}