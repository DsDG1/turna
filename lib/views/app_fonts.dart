import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// GoogleFonts wrapper that is HarmonyOS-safe.
///
/// `google_fonts` fetches font files via HTTP at runtime and, when
/// `allowRuntimeFetching` is disabled, throws an uncaught platform error if
/// the font is not bundled as an asset. HarmonyOS has no GMS / may be offline,
/// so we bypass GoogleFonts entirely on OHos and return a plain [TextStyle]
/// using the system default font family. On every other platform the real
/// GoogleFonts implementation is used.
class AppFonts {
  AppFonts._();

  /// Whether to bypass [GoogleFonts] on this platform.
  static bool get _bypass =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.ohos;

  /// Nunito (used by splash + onboarding).
  static TextStyle nunito({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    if (_bypass) {
      return TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing ?? 0.0,
        height: height,
      );
    }
    return GoogleFonts.nunito(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Lexend (dyslexia-friendly text theme).
  static TextStyle lexend({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
  }) {
    if (_bypass) {
      return TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      );
    }
    return GoogleFonts.lexend(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  /// Replaces [GoogleFonts.lexendTextTheme] so the whole text theme is swapped
  /// for Lexend when the dyslexia-font toggle is on.
  static TextTheme lexendTextTheme(TextTheme base) {
    if (_bypass) return base;
    return GoogleFonts.lexendTextTheme(base);
  }
}
