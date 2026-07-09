// Flutter imports:
import 'package:flutter/material.dart';

/// Varnamala Peacock Theme
/// A vibrant theme inspired by peacock feathers with teal, cyan, and emerald tones
class VarnamalaTheme {
  VarnamalaTheme._();

  // PRIMARY PEACOCK COLORS
  static const Color peacockDeep = Color(0xFF1A0285);
  static const Color peacockTeal = Color(0xFF1F727E);
  static const Color peacockCyan = Color(0xFF359CBB);
  static const Color peacockTurquoise = Color(0xFF46D1BF);
  static const Color peacockMint = Color(0xFF00FFC6);

  // SEMANTIC COLORS
  static const Color primary = peacockTeal;
  static const Color primaryLight = peacockCyan;
  static const Color primaryDark = Color(0xFF145A64);
  static const Color secondary = peacockTurquoise;
  static const Color secondaryLight = peacockMint;
  static const Color error = Color(0xFFE74C3C);
  static const Color errorLight = Color(0xFFFF6B6B);
  static const Color errorDark = Color(0xFFC0392B);
  static const Color success = Color(0xFFFFD93D);
  static const Color successLight = Color(0xFFFFE066);
  static const Color successDark = Color(0xFFE5C235);
  static const Color warning = Color(0xFFFF9F43);
  static const Color warningLight = Color(0xFFFFBE76);
  static const Color info = peacockCyan;

  // BACKGROUND COLORS
  static const Color background = Color(0xFFF8FFFE);
  static const Color surface = Colors.white;
  static const Color scaffoldBackground = Color(0xFFF5FDFB);
  static const Color cardBackground = Colors.white;
  static const Color elevatedSurface = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFEEF2F1);

  // TEXT COLORS
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF4A5568);
  static const Color textHint = Color(0xFF9CA3AF);
  static const Color textOnPrimary = Colors.white;
  static const Color textOnSecondary = Colors.white;

  // LEAGUE COLORS (Jewel Tones)
  static const Color leagueBronze = Color(0xFFCD7F32);
  static const Color leagueSilver = Color(0xFFC0C0C0);
  static const Color leagueGold = Color(0xFFFFD700);
  static const Color leagueAmethyst = Color(0xFF9B59B6);
  static const Color leaguePearl = Color(0xFFF5F5F5);
  static const Color leagueRuby = Color(0xFFE74C3C);
  static const Color leagueEmerald = Color(0xFF27AE60);
  static const Color leagueDiamond = Color(0xFF3498DB);

  // GRADIENTS
  static const LinearGradient peacockGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [peacockDeep, peacockTeal, peacockCyan],
  );

  static const LinearGradient softGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF8FFFE), Color(0xFFE8F8F5)],
  );

  static const LinearGradient courseTreeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFF0FFFC),
      Color(0xFFE8F8F5),
      Color(0xFFE0F5F1),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static LinearGradient courseTreeGradientFor(BuildContext context) =>
      _isDark(context)
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0F1C1A),
                Color(0xFF142624),
                Color(0xFF1A2E2B),
              ],
              stops: [0.0, 0.5, 1.0],
            )
          : courseTreeGradient;

  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [peacockCyan, peacockTurquoise],
  );

  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [success, successLight],
  );

  static const RadialGradient nodeGlowGradient = RadialGradient(
    colors: [
      Color(0x4046D1BF),
      Color(0x2046D1BF),
      Color(0x0046D1BF),
    ],
  );

  // SHADOWS
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: peacockTeal.withValues(alpha: 0.08),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: peacockTeal.withValues(alpha: 0.1),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ];

  static List<BoxShadow> get glowShadow => [
        BoxShadow(
          color: peacockMint.withValues(alpha: 0.3),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ];

  static List<BoxShadow> get buttonShadow => [
        BoxShadow(
          color: peacockTeal.withValues(alpha: 0.3),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];

  // BORDER RADIUS
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;
  static const double radiusRound = 100.0;

  // SEMANTIC TINT TOKENS
  // Common alpha-blended fills & borders used across feature widgets.
  // Non-const because `withValues` is computed at runtime.
  static final Color tintLight = peacockTeal.withValues(alpha: 0.06);
  static final Color tintSoft = peacockTeal.withValues(alpha: 0.08);
  static final Color tintMedium = peacockTeal.withValues(alpha: 0.12);
  static final Color borderMuted = textHint.withValues(alpha: 0.25);

  // THEME-AWARE COLOR HELPERS
  // Use these instead of hard-coded Colors.white / Color(0xFF...) so widgets
  // automatically adapt when the app switches between light and dark mode.

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color surfaceColor(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  static Color scaffoldBg(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  static Color cardBg(BuildContext context) => _isDark(context)
      ? const Color(0xFF1A2E2B)
      : Colors.white;

  static Color elevatedCardBg(BuildContext context) => _isDark(context)
      ? const Color(0xFF1A2E2B)
      : const Color(0xFFFFFFFF);

  static Color dividerBg(BuildContext context) => _isDark(context)
      ? const Color(0xFF2A4540)
      : const Color(0xFFEEF2F1);

  static Color textPrimaryColor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color textSecondaryColor(BuildContext context) => _isDark(context)
      ? const Color(0xFFB0CBC7)
      : const Color(0xFF4A5568);

  static Color textHintColor(BuildContext context) => _isDark(context)
      ? const Color(0xFF6B8A85)
      : const Color(0xFF9CA3AF);

  static Color inputFillColor(BuildContext context) => _isDark(context)
      ? const Color(0xFF142624)
      : const Color(0xFFF5F8F7);

  static Color statCardBorder(BuildContext context) => _isDark(context)
      ? const Color(0xFF2A4540)
      : const Color(0xFFEEF2F1);

  static Color bottomNavBg(BuildContext context) => _isDark(context)
      ? const Color(0xFF1A2E2B)
      : Colors.white;

  static Color streakChipBg(BuildContext context) => _isDark(context)
      ? const Color(0xFF3E2723)
      : const Color(0xFFFFF3E0);

  static Color streakChipText(BuildContext context) => _isDark(context)
      ? const Color(0xFFFFB74D)
      : const Color(0xFFFF9500);

  static Color scoreChipBg(BuildContext context) => _isDark(context)
      ? const Color(0xFF4A3B00)
      : const Color(0xFFFFF8E1);

  static Color scoreChipText(BuildContext context) => _isDark(context)
      ? const Color(0xFFFFD54F)
      : const Color(0xFFE5A800);

  // MATERIAL THEME DATA
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: primary,
        scaffoldBackgroundColor: scaffoldBackground,
        colorScheme: const ColorScheme.light(
          primary: primary,
          primaryContainer: primaryLight,
          secondary: secondary,
          secondaryContainer: secondaryLight,
          surface: surface,
          error: error,
          onPrimary: textOnPrimary,
          onSecondary: textOnSecondary,
          onSurface: textPrimary,
          onError: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: textPrimary,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          iconTheme: IconThemeData(color: peacockTeal),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: cardBackground,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: textOnPrimary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primary,
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: const BorderSide(color: primary, width: 2),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F8F7),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: error, width: 2),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: peacockTeal,
          unselectedItemColor: textHint,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: peacockTurquoise,
          linearTrackColor: Color(0xFFE0E0E0),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: peacockTurquoise,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFEEF2F1),
          thickness: 1,
        ),
        textTheme: const TextTheme(
          displayLarge:
              TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
          displayMedium:
              TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
          displaySmall:
              TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
          headlineLarge:
              TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
          headlineMedium:
              TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
          headlineSmall:
              TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
          titleLarge:
              TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
          titleMedium:
              TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
          titleSmall:
              TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(color: textPrimary),
          bodyMedium: TextStyle(color: textSecondary),
          bodySmall: TextStyle(color: textHint),
          labelLarge:
              TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
          labelMedium: TextStyle(color: textSecondary),
          labelSmall: TextStyle(color: textHint),
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: primary,
        scaffoldBackgroundColor: const Color(0xFF0F1C1A),
        colorScheme: const ColorScheme.dark(
          primary: primary,
          primaryContainer: primaryLight,
          secondary: secondary,
          secondaryContainer: secondaryLight,
          surface: Color(0xFF1A2E2B),
          error: error,
          onPrimary: textOnPrimary,
          onSecondary: textOnSecondary,
          onSurface: Colors.white,
          onError: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          backgroundColor: Color(0xFF1A2E2B),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          iconTheme: IconThemeData(color: peacockTurquoise),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFF1A2E2B),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: textOnPrimary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: peacockTurquoise,
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: peacockTurquoise,
            side: const BorderSide(color: primary, width: 2),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF142624),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: error, width: 2),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1A2E2B),
          selectedItemColor: peacockTurquoise,
          unselectedItemColor: Color(0xFF6B8A85),
          showSelectedLabels: false,
          showUnselectedLabels: false,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: peacockTurquoise,
          linearTrackColor: Color(0xFF2A4540),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: peacockTurquoise,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF2A4540),
          thickness: 1,
        ),
        textTheme: const TextTheme(
          displayLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          displayMedium:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          displaySmall:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          headlineLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          headlineMedium:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          headlineSmall:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          titleLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          titleMedium:
              TextStyle(color: Color(0xFFB0CBC7), fontWeight: FontWeight.w500),
          titleSmall:
              TextStyle(color: Color(0xFFB0CBC7), fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Color(0xFFB0CBC7)),
          bodySmall: TextStyle(color: Color(0xFF6B8A85)),
          labelLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          labelMedium: TextStyle(color: Color(0xFFB0CBC7)),
          labelSmall: TextStyle(color: Color(0xFF6B8A85)),
        ),
      );
}

// LEGACY SUPPORT
const primaryColor = VarnamalaTheme.primary;
