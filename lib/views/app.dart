// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/accessibility_provider.dart';
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
      child: _AppShell(),
    );
  }
}

/// Resolves the active theme + accessibility overrides, then builds
/// [MaterialApp.router]. Watching both [ThemeProvider] and
/// [AccessibilityProvider] in one selector avoids two separate rebuilds and
/// keeps the theme/MediaQuery decisions consistent.
class _AppShell extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<ThemeProvider, ThemeMode>(
      (p) => p.themeMode,
    );
    final acc = context.select<AccessibilityProvider, _AccSnapshot>(
      (p) => _AccSnapshot(
        textScaler: p.textScaler,
        reducedMotion: p.reducedMotion,
        highContrast: p.highContrast,
        dyslexiaFont: p.dyslexiaFont,
      ),
    );

    final ThemeData light;
    final ThemeData dark;
    if (acc.highContrast) {
      light = VarnamalaTheme.highContrastLightTheme;
      dark = VarnamalaTheme.highContrastDarkTheme;
    } else {
      light = VarnamalaTheme.lightTheme;
      dark = VarnamalaTheme.darkTheme;
    }
    // Swap the entire text theme for a dyslexia-friendly font (Lexend) when
    // requested. GoogleFonts.<font>TextTheme preserves colors/weights from the
    // base theme's text styles.
    final theme = acc.dyslexiaFont
        ? light.copyWith(textTheme: GoogleFonts.lexendTextTheme(light.textTheme))
        : light;
    final darkTheme = acc.dyslexiaFont
        ? dark.copyWith(textTheme: GoogleFonts.lexendTextTheme(dark.textTheme))
        : dark;

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Varnamala',
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      routerConfig: router.config(),
      builder: (context, child) {
        // Apply the accessibility MediaQuery overrides at the root so every
        // descendant inherits them: text magnification and (when reduced
        // motion is on) Flutter's accessibleNavigation / disableAnimations
        // flags, which make AnimatedSwitcher / page transitions resolve
        // instantly.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: acc.textScaler,
            accessibleNavigation: acc.reducedMotion || mq.accessibleNavigation,
            disableAnimations:
                acc.reducedMotion ? true : mq.disableAnimations,
          ),
          child: child!,
        );
      },
    );
  }
}

class _AccSnapshot {
  const _AccSnapshot({
    required this.textScaler,
    required this.reducedMotion,
    required this.highContrast,
    required this.dyslexiaFont,
  });

  final TextScaler textScaler;
  final bool reducedMotion;
  final bool highContrast;
  final bool dyslexiaFont;

  @override
  bool operator ==(Object other) =>
      other is _AccSnapshot &&
      other.textScaler == textScaler &&
      other.reducedMotion == reducedMotion &&
      other.highContrast == highContrast &&
      other.dyslexiaFont == dyslexiaFont;

  @override
  int get hashCode =>
      Object.hash(textScaler, reducedMotion, highContrast, dyslexiaFont);
}