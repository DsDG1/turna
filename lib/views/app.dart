// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/providers.dart';
import 'package:turna/application/theme_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/routing/routing.dart';
import 'package:turna/views/app_fonts.dart';
import 'package:turna/views/theme.dart';

final router = getIt<AppRouter>();

class TurnaApp extends StatelessWidget {
  const TurnaApp({Key? key}) : super(key: key);

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
class _AppShell extends StatefulWidget {
  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  late final _routeConfig = router.config();

  @override
  void initState() {
    super.initState();
  }

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
      light = TurnaTheme.highContrastLightTheme;
      dark = TurnaTheme.highContrastDarkTheme;
    } else {
      light = TurnaTheme.lightTheme;
      dark = TurnaTheme.darkTheme;
    }
    final theme = acc.dyslexiaFont
        ? light.copyWith(textTheme: AppFonts.lexendTextTheme(light.textTheme))
        : light;
    final darkTheme = acc.dyslexiaFont
        ? dark.copyWith(textTheme: AppFonts.lexendTextTheme(dark.textTheme))
        : dark;

    return _OrientationController(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Turna',
        theme: theme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        routerConfig: _routeConfig,
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
              accessibleNavigation:
                  acc.reducedMotion || mq.accessibleNavigation,
              disableAnimations:
                  acc.reducedMotion ? true : mq.disableAnimations,
            ),
            child: child!,
          );
        },
      ),
    );
  }
}

/// Applies the user's auto-rotation preference at runtime.
///
/// [main] locks orientation before the first frame; this controller keeps it
/// in sync when the user toggles the setting (Settings > 外观 > 自动旋转屏幕).
/// Default off = portrait-only; on = follow device orientation.
class _OrientationController extends StatefulWidget {
  final Widget child;

  const _OrientationController({required this.child});

  @override
  State<_OrientationController> createState() => _OrientationControllerState();
}

class _OrientationControllerState extends State<_OrientationController> {
  late bool _autoRotate;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _autoRotate = settings.autoRotateEnabled;
    settings.addListener(_onSettingsChanged);
    _apply();
  }

  void _onSettingsChanged() {
    final settings = context.read<SettingsProvider>();
    if (settings.autoRotateEnabled == _autoRotate) return;
    _autoRotate = settings.autoRotateEnabled;
    _apply();
  }

  void _apply() {
    SystemChrome.setPreferredOrientations(
      _autoRotate ? [] : [DeviceOrientation.portraitUp],
    );
  }

  @override
  void dispose() {
    context.read<SettingsProvider>().removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
