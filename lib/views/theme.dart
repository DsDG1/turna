// Dart imports:
import 'dart:math' as math;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Turna Brand Theme —「湿地鹤」visual system (ADR 0033).
///
/// **Area ratio (70 / 20 / 10):**
/// - ~70% mist neutrals: scaffold / surface / card / text
/// - ~20% wetland cool axis: [brandNavy] → [brandTeal] → [brandSky] → [brandReed]
/// - ~10% warm Anatolian accents: [anatolianClay] / [warmSand]
///
/// **Primary CTA:** always teal ([buttonGradient] = teal → tealLight).
/// Clay is secondary brand only — markers, chips, brand strips; never main CTA fill.
///
/// **Single source of truth** with GUI `tool/gui/src/theme_tokens.py` (BRAND_*).
/// Scheme A locked: brandTeal = `#1F727E`. Brand tokens only — no legacy color aliases.
class TurnaTheme {
  TurnaTheme._();

  // ---------------------------------------------------------------------------
  // TURNA BRAND COLORS (core contract — keep in sync with theme_tokens.py)
  // ---------------------------------------------------------------------------
  /// Deep silhouette / night water — shadows, gradient start.
  static const Color brandNavy = Color(0xFF19324A);

  /// Primary brand / main CTA fill / links / selected chrome.
  static const Color brandTeal = Color(0xFF1F727E);

  /// Primary hover / button gradient end.
  static const Color brandTealLight = Color(0xFF2F7F8E);

  /// Pressed / darker primary (≡ GUI `BRAND_TEAL_DARK`).
  static const Color brandTealDark = Color(0xFF145A64);

  /// Info / listening / secondary cool accent.
  static const Color brandSky = Color(0xFF4A95A8);

  /// Glow / dark-mode icon highlight — never large light-surface body text.
  static const Color brandReed = Color(0xFF78C7B8);

  /// Second brand (warm) — complete/perfect markers, achievement chips, brand strip.
  static const Color anatolianClay = Color(0xFFB85C3F);

  /// Warm light fill / secondaryContainer / sand strip under clay accents.
  static const Color warmSand = Color(0xFFEAD9B8);

  // SEMANTIC COLORS
  static const Color primary = brandTeal;
  static const Color primaryLight = brandTealLight;
  static const Color primaryDark = brandTealDark;
  static const Color secondary = anatolianClay;
  static const Color secondaryLight = warmSand;
  static const Color error = Color(0xFFE74C3C);
  static const Color errorLight = Color(0xFFFF6B6B);
  static const Color errorDark = Color(0xFFC0392B);
  static const Color success = Color(0xFFFFD93D);
  static const Color successLight = Color(0xFFFFE066);
  static const Color successDark = Color(0xFFE5C235);
  static const Color warning = Color(0xFFFF9F43);
  static const Color warningLight = Color(0xFFFFBE76);
  static const Color info = brandSky;

  // JEWEL TONES - distinct accents for feature surfaces (e.g. AI).
  static const Color amethystLeague = Color(0xFF9B59B6);

  // BACKGROUND COLORS
  static const Color background = Color(0xFFF7FAF9);
  static const Color surface = Colors.white;
  static const Color scaffoldBackground = Color(0xFFF3F8F7);
  static const Color cardBackground = Colors.white;
  static const Color elevatedSurface = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE3EBE9);

  /// Dark scaffold / window chrome (≡ Android `turna_scaffold_dark`).
  static const Color darkScaffold = Color(0xFF101B22);

  /// Dark AppBar / status bar surface (≡ Android `turna_appbar_dark`).
  static const Color darkAppBar = Color(0xFF182832);

  // TEXT COLORS
  static const Color textPrimary = Color(0xFF1C2730);
  static const Color textSecondary = Color(0xFF52616B);
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
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandNavy, brandTeal, brandSky],
  );

  static const LinearGradient softGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF7FAF9), Color(0xFFE8F2F0)],
  );

  static const LinearGradient courseTreeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFF7FAF9),
      Color(0xFFEFF7F5),
      Color(0xFFE8F2F0),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static LinearGradient courseTreeGradientFor(BuildContext context) =>
      _isDark(context)
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF101B22),
                Color(0xFF142129),
                Color(0xFF182832),
              ],
              stops: [0.0, 0.5, 1.0],
            )
          : courseTreeGradient;

  /// Main CTA / primary FAB gradient — teal only (never insert clay).
  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandTeal, brandTealLight],
  );

  /// Alias for [buttonGradient]. Prefer either name; both are teal → tealLight.
  static const LinearGradient brandPrimaryGradient = buttonGradient;

  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [success, successLight],
  );

  /// Soft reed glow under course nodes — alphas derived from [brandReed].
  static final RadialGradient nodeGlowGradient = RadialGradient(
    colors: [
      brandReed.withValues(alpha: 0.15),
      brandReed.withValues(alpha: 0.07),
      brandReed.withValues(alpha: 0.0),
    ],
  );

  /// Box decoration for primary CTAs (teal → tealLight). Never insert clay.
  static BoxDecoration primaryCtaDecoration({
    BorderRadius? borderRadius,
    bool elevated = true,
  }) {
    final radius =
        borderRadius ?? BorderRadius.circular(radiusMedium);
    return BoxDecoration(
      gradient: buttonGradient,
      borderRadius: radius,
      boxShadow: elevated ? buttonShadow : null,
    );
  }

  // ---------------------------------------------------------------------------
  // SYSTEM UI (status / navigation bar) — surface-aligned, not brandTeal fill
  // ---------------------------------------------------------------------------

  /// Light AppBar / status / nav chrome (white) with dark icons.
  static const SystemUiOverlayStyle lightSystemUiOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.white,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );

  /// Dark AppBar / status / nav chrome with light icons.
  static const SystemUiOverlayStyle darkSystemUiOverlay = SystemUiOverlayStyle(
    statusBarColor: darkAppBar,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: darkAppBar,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  );

  /// High-contrast light: pure white chrome, dark icons.
  static const SystemUiOverlayStyle highContrastLightSystemUiOverlay =
      SystemUiOverlayStyle(
    statusBarColor: Colors.white,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );

  /// High-contrast dark: pure black chrome, light icons.
  static const SystemUiOverlayStyle highContrastDarkSystemUiOverlay =
      SystemUiOverlayStyle(
    statusBarColor: Colors.black,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  );

  /// Status/nav bar style for the active [brightness] and high-contrast flag.
  ///
  /// Aligns with AppBar surfaces (not [brandTeal]). Call from the app shell
  /// when theme mode or high-contrast changes so pages without an AppBar
  /// still update Android chrome.
  static SystemUiOverlayStyle systemUiOverlayFor({
    required Brightness brightness,
    bool highContrast = false,
  }) {
    if (highContrast) {
      return brightness == Brightness.dark
          ? highContrastDarkSystemUiOverlay
          : highContrastLightSystemUiOverlay;
    }
    return brightness == Brightness.dark
        ? darkSystemUiOverlay
        : lightSystemUiOverlay;
  }

  /// WCAG relative contrast ratio between [foreground] and [background].
  /// Used by theme contract tests and any a11y checks.
  static double contrastRatio(Color foreground, Color background) {
    final l1 = _relativeLuminance(foreground);
    final l2 = _relativeLuminance(background);
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static double _relativeLuminance(Color color) {
    double linearize(double channel) {
      return channel <= 0.03928
          ? channel / 12.92
          : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = linearize(color.r);
    final g = linearize(color.g);
    final b = linearize(color.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  // SHADOWS
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: brandNavy.withValues(alpha: 0.07),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: brandNavy.withValues(alpha: 0.08),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ];

  static List<BoxShadow> get glowShadow => [
        BoxShadow(
          color: brandReed.withValues(alpha: 0.18),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ];

  static List<BoxShadow> get buttonShadow => [
        BoxShadow(
          color: brandNavy.withValues(alpha: 0.22),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];

  /// 「半拟物质感」大卡片: Anki / ShowWord / Reading 主卡专用.
  /// 双层阴影 (远大 + 近小) 模拟光照下的悬浮磨砂面.
  static List<BoxShadow> get elevatedCardShadow => [
        BoxShadow(
          color: brandNavy.withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: brandNavy.withValues(alpha: 0.05),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  /// 选项条 / 输入框 / 副卡: 浅短阴影.
  static List<BoxShadow> get raisedCardShadow => [
        BoxShadow(
          color: brandNavy.withValues(alpha: 0.06),
          blurRadius: 14,
          offset: const Offset(0, 6),
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
  static final Color tintLight = brandTeal.withValues(alpha: 0.06);
  static final Color tintSoft = brandTeal.withValues(alpha: 0.08);
  static final Color tintMedium = brandTeal.withValues(alpha: 0.12);
  static final Color borderMuted = textHint.withValues(alpha: 0.25);

  // FROSTED GLASS TOKENS
  // 半拟物彩色玻璃质感所需的主题感知 helper。
  // 调用方按 context 读取，自动适配浅/深色。
  // light: 用高 alpha 白底保持亮堂；dark: 改为低 alpha 白底以避免死白。

  /// 玻璃卡片底层白色霜面。
  static Color glassSurface(BuildContext context) => _isDark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.white.withValues(alpha: 0.55);

  /// 玻璃卡片顶边白色高光。
  static Color glassHighlight(BuildContext context) => _isDark(context)
      ? Colors.white.withValues(alpha: 0.18)
      : Colors.white.withValues(alpha: 0.70);

  /// 玻璃卡片 1px 描边颜色。
  static Color glassBorder(BuildContext context) => _isDark(context)
      ? Colors.white.withValues(alpha: 0.15)
      : Colors.white.withValues(alpha: 0.50);

  /// 玻璃着色层：accent × 低 alpha，让每张卡读作对应色玻璃。
  /// 浅深色均使用 0.22 alpha，深色模式下整体暗调由 [glassSurface] 和
  /// [glassHighlight] 的深色分支承担，避免此处再分叉。
  static Color glassAccentFill(Color accent) => accent.withValues(alpha: 0.22);

  /// 玻璃阴影：双层（accent + 黑色微影），按深浅微调 alpha。
  static List<BoxShadow> glassShadow(BuildContext context, Color accent) =>
      _isDark(context)
          ? [
              BoxShadow(
                color: accent.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ]
          : [
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ];

  /// 按钮整体羽化光晕：练习卡 SoftCard 外层散出的白色柔光。
  /// 深色分支用「负 spread + 大模糊」：阴影形状向内收缩后由模糊主导，
  /// 形成弥散光晕而不是贴着边缘的亮环（贴边亮环会在圆角处堆出亮角）。
  /// 用法：加到 SoftCard Ink 的 boxShadow 列表里（与现有 softCardShadow 叠加）。
  static List<BoxShadow> featheredButtonGlow(BuildContext context) =>
      _isDark(context)
          ? [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.10),
                blurRadius: 48,
                spreadRadius: -14,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.06),
                blurRadius: 40,
                spreadRadius: -10,
                offset: const Offset(0, 14),
              ),
            ]
          : [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.45),
                blurRadius: 14,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.20),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ];

  /// 玻璃徽章实色填充：badge 仍走 accent 实色，仅加 1px 高光描边和小阴影。
  static Color glassBadgeFill(Color accent) => accent;

  // SOFT TINTED TOKENS
  // 「轻量着色卡」所需的主题感知 helper：底色 + 内侧晕染 + 文字提亮。
  // 浅色用低 alpha accent（≈ 0.10）罩白底；深色改为「不透明暗面 + accent
  // 罩染」，避免半透明色叠在深色渐变背景上发灰发浑。
  // 用法：SoftCard 的 fill 直接传 accent，外部按 context 自动适配。

  /// tinted 卡片底色：浅色为 accent @ 0.10 罩白；深色为 accent @ 0.10
  /// 不透明罩染在抬升暗面上——只留淡淡色相，接近「学习」section 卡的
  /// 中性暗面质感，色彩由 icon chip 与提亮文字承载。
  /// Soft fill for accent cards. Default alpha 0.10; raise slightly (e.g. 0.16)
  /// for secondary-brand tiles that need higher visibility.
  static Color softTint(
    BuildContext context,
    Color accent, {
    double alpha = 0.10,
  }) =>
      _isDark(context)
          ? Color.alphaBlend(
              accent.withValues(alpha: alpha),
              const Color(0xFF182832),
            )
          : Color.alphaBlend(
              accent.withValues(alpha: alpha),
              Colors.white,
            );

  /// 着色卡内侧顶部白色晕染：模拟光照打在霜面上的高光。
  /// 用法：SoftCard 在 ClipRRect 内用 DecoratedBox 叠加在 child 之下。
  static LinearGradient softCardSheen(BuildContext context) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: _isDark(context) ? 0.07 : 0.20),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5],
      );

  /// 着色卡上的 accent 文字/图标色：浅色直接用 accent；深色向白色提亮
  /// 35%，保证 teal/cyan 这类深 accent 在暗底上可读。
  static Color accentOnCard(BuildContext context, Color accent) =>
      _isDark(context) ? Color.lerp(accent, Colors.white, 0.35)! : accent;

  /// tinted 卡片柔和阴影：浅色 accent @ 0.10 向下投影；深色负 spread +
  /// 大模糊弥散，避免贴边亮环在圆角处堆出亮角。
  static List<BoxShadow> softCardShadow(BuildContext context, Color accent) => [
        BoxShadow(
          color: accent.withValues(alpha: _isDark(context) ? 0.12 : 0.10),
          blurRadius: _isDark(context) ? 24 : 12,
          spreadRadius: _isDark(context) ? -6 : 0,
          offset: _isDark(context) ? Offset.zero : const Offset(0, 4),
        ),
      ];

  // THEME-AWARE COLOR HELPERS
  // Use these instead of hard-coded Colors.white / Color(0xFF...) so widgets
  // automatically adapt when the app switches between light and dark mode.

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color surfaceColor(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  static Color scaffoldBg(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  static Color cardBg(BuildContext context) =>
      _isDark(context) ? const Color(0xFF182832) : Colors.white;

  static Color elevatedCardBg(BuildContext context) =>
      _isDark(context) ? const Color(0xFF20323D) : const Color(0xFFFFFFFF);

  static Color dividerBg(BuildContext context) =>
      _isDark(context) ? const Color(0xFF2B414C) : divider;

  static Color textPrimaryColor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color textSecondaryColor(BuildContext context) =>
      _isDark(context) ? const Color(0xFFB6C4CB) : textSecondary;

  static Color textHintColor(BuildContext context) =>
      _isDark(context) ? const Color(0xFF7D929C) : textHint;

  static Color inputFillColor(BuildContext context) =>
      _isDark(context) ? const Color(0xFF142129) : const Color(0xFFF3F8F7);

  static Color statCardBorder(BuildContext context) =>
      _isDark(context) ? const Color(0xFF2B414C) : divider;

  static Color bottomNavBg(BuildContext context) =>
      _isDark(context) ? const Color(0xFF182832) : Colors.white;

  /// Frosted fill for the floating home tab bar. More opaque than
  /// [glassSurface] so labels stay readable over scrolling content.
  static Color floatingBarFill(BuildContext context) => _isDark(context)
      ? const Color(0xFF182832).withValues(alpha: 0.78)
      : Colors.white.withValues(alpha: 0.82);

  /// Stadium chips with a soft selected fill — a light M3 Expressive nudge
  /// without swapping in connected button-group widgets.
  static ChipThemeData expressiveChipTheme({
    required Color background,
    required Color selectedFill,
    required Color label,
    required Color selectedLabel,
    required Color outline,
    bool highContrast = false,
  }) {
    final side = BorderSide(color: outline, width: highContrast ? 1.5 : 1);
    return ChipThemeData(
      backgroundColor: background,
      selectedColor: selectedFill,
      secondarySelectedColor: selectedFill,
      disabledColor: background,
      checkmarkColor: selectedLabel,
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: label,
      ),
      secondaryLabelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: selectedLabel,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      shape: StadiumBorder(side: side),
      side: side,
    );
  }

  /// Rounder segmented control; selected segment uses a teal wash.
  static SegmentedButtonThemeData expressiveSegmentedTheme({
    required Color selectedFill,
    required Color selectedForeground,
    required Color foreground,
    required Color outline,
    bool highContrast = false,
  }) {
    return SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: WidgetStateProperty.all(
          BorderSide(color: outline, width: highContrast ? 1.5 : 1),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return selectedFill;
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return selectedForeground;
          }
          return foreground;
        }),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusRound),
          ),
        ),
      ),
    );
  }

  static Color streakChipBg(BuildContext context) =>
      _isDark(context) ? const Color(0xFF3E2723) : const Color(0xFFFFF3E0);

  static Color streakChipText(BuildContext context) =>
      _isDark(context) ? const Color(0xFFFFB74D) : const Color(0xFFFF9500);

  static Color scoreChipBg(BuildContext context) =>
      _isDark(context) ? const Color(0xFF4A3B00) : const Color(0xFFFFF8E1);

  static Color scoreChipText(BuildContext context) =>
      _isDark(context) ? const Color(0xFFFFD54F) : const Color(0xFFE5A800);

  /// Tinted surface for warning / hint banners (FSRS risk, experimental
  /// warnings, etc.). Replaces hard-coded `Color(0xFFFFF3E0)` in legacy
  /// settings sub-pages. Dark variant is a low-alpha warm brown that won't
  /// "贴亮块" on the dark scaffold.
  static Color warningSurface(BuildContext context) =>
      _isDark(context) ? const Color(0xFF3A2A14) : const Color(0xFFFFF3E0);

  /// Tinted surface for success / safe-state banners (cache cleared,
  /// database intact, etc.). Dark variant is a low-alpha deep green.
  static Color successSurface(BuildContext context) =>
      _isDark(context) ? const Color(0xFF1F3A2A) : const Color(0xFFE8F5E9);

  /// Tinted surface for danger / destructive-state banners (safe mode,
  /// critical alert, etc.). Dark variant is a low-alpha deep red.
  static Color dangerSurface(BuildContext context) =>
      _isDark(context) ? const Color(0xFF3A1414) : const Color(0xFFFFEBEE);

  // ---------------------------------------------------------------------------
  // CLAY / SAND HELPERS (secondary brand — restrained warm accents)
  // ---------------------------------------------------------------------------

  /// Solid clay accent (icons, small pills). Prefer over hard-coded hex.
  static Color clayAccent(BuildContext context) => anatolianClay;

  /// Soft clay tint for secondary soft-tint cards (Play Hub optional tile, etc.).
  static Color claySoftTint(BuildContext context) => softTint(context, anatolianClay);

  /// Warm sand surface for brand strips / chip fills under clay accents.
  static Color clayOnSandFill(BuildContext context) =>
      _isDark(context) ? anatolianClay.withValues(alpha: 0.18) : warmSand;

  /// Readable clay (or navy if sand contrast is weak) on sand-like fills.
  static Color clayOnSandText(BuildContext context) => anatolianClay;

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
          systemOverlayStyle: lightSystemUiOverlay,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          iconTheme: IconThemeData(color: brandTeal),
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
          fillColor: const Color(0xFFF3F8F7),
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
          backgroundColor: Colors.transparent,
          selectedItemColor: brandTeal,
          unselectedItemColor: textHint,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        chipTheme: expressiveChipTheme(
          background: const Color(0xFFF3F8F7),
          selectedFill: brandTeal.withValues(alpha: 0.16),
          label: textSecondary,
          selectedLabel: brandTeal,
          outline: divider,
        ),
        segmentedButtonTheme: expressiveSegmentedTheme(
          selectedFill: brandTeal.withValues(alpha: 0.16),
          selectedForeground: brandTeal,
          foreground: textSecondary,
          outline: divider,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: brandTeal,
          linearTrackColor: Color(0xFFE0E0E0),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: brandTeal,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        dividerTheme: const DividerThemeData(
          color: divider,
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
        scaffoldBackgroundColor: darkScaffold,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          primaryContainer: primaryLight,
          secondary: secondary,
          secondaryContainer: secondaryLight,
          surface: darkAppBar,
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
          backgroundColor: darkAppBar,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: darkSystemUiOverlay,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          iconTheme: IconThemeData(color: brandReed),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFF182832),
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
            foregroundColor: brandReed,
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: brandReed,
            side: const BorderSide(color: primary, width: 2),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF142129),
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
          backgroundColor: Colors.transparent,
          selectedItemColor: brandReed,
          unselectedItemColor: Color(0xFF7D929C),
          showSelectedLabels: true,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        chipTheme: expressiveChipTheme(
          background: const Color(0xFF142129),
          selectedFill: brandTeal.withValues(alpha: 0.28),
          label: const Color(0xFFB6C4CB),
          selectedLabel: brandReed,
          outline: const Color(0xFF2B414C),
        ),
        segmentedButtonTheme: expressiveSegmentedTheme(
          selectedFill: brandTeal.withValues(alpha: 0.28),
          selectedForeground: brandReed,
          foreground: const Color(0xFFB6C4CB),
          outline: const Color(0xFF2B414C),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: brandTealLight,
          linearTrackColor: Color(0xFF2B414C),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: brandTeal,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF2B414C),
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
              TextStyle(color: Color(0xFFB6C4CB), fontWeight: FontWeight.w500),
          titleSmall:
              TextStyle(color: Color(0xFFB6C4CB), fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Color(0xFFB6C4CB)),
          bodySmall: TextStyle(color: Color(0xFF7D929C)),
          labelLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          labelMedium: TextStyle(color: Color(0xFFB6C4CB)),
          labelSmall: TextStyle(color: Color(0xFF7D929C)),
        ),
      );

  /// High-contrast variant of [lightTheme] for low-vision / sensory needs.
  ///
  /// Pure white surfaces, near-black text, stronger borders, and a heavier
  /// focus ring — derived from [lightTheme] so only the contrast-relevant
  /// tokens change.
  static ThemeData get highContrastLightTheme => lightTheme.copyWith(
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: primaryDark,
          primaryContainer: primary,
          secondary: primaryDark,
          secondaryContainer: primary,
          surface: Colors.white,
          error: errorDark,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.black,
          onError: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: highContrastLightSystemUiOverlay,
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
          iconTheme: IconThemeData(color: primaryDark),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
            side: const BorderSide(color: Colors.black, width: 1.5),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: Colors.black, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: Colors.black, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: primaryDark, width: 2.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: errorDark, width: 2),
          ),
        ),
        chipTheme: expressiveChipTheme(
          background: Colors.white,
          selectedFill: primaryDark.withValues(alpha: 0.18),
          label: Colors.black,
          selectedLabel: primaryDark,
          outline: Colors.black,
          highContrast: true,
        ),
        segmentedButtonTheme: expressiveSegmentedTheme(
          selectedFill: primaryDark.withValues(alpha: 0.18),
          selectedForeground: primaryDark,
          foreground: Colors.black,
          outline: Colors.black,
          highContrast: true,
        ),
        dividerTheme: const DividerThemeData(
          color: Colors.black54,
          thickness: 1,
        ),
        textTheme: const TextTheme(
          displayLarge:
              TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          displayMedium:
              TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          displaySmall:
              TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          headlineLarge:
              TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
          headlineMedium:
              TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
          headlineSmall:
              TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
          titleLarge:
              TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
          titleMedium:
              TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
          titleSmall:
              TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(color: Colors.black),
          bodyMedium: TextStyle(color: Color(0xFF1A1A2E)),
          bodySmall: TextStyle(color: Color(0xFF2D2D44)),
          labelLarge:
              TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
          labelMedium: TextStyle(color: Color(0xFF1A1A2E)),
          labelSmall: TextStyle(color: Color(0xFF2D2D44)),
        ),
      );

  /// High-contrast variant of [darkTheme] for low-vision / sensory needs.
  ///
  /// Near-black surfaces, pure white text, stronger borders — derived from
  /// [darkTheme] so only the contrast-relevant tokens change.
  static ThemeData get highContrastDarkTheme => darkTheme.copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: brandReed,
          primaryContainer: brandTealLight,
          secondary: brandReed,
          secondaryContainer: brandTealLight,
          surface: Colors.black,
          error: errorLight,
          onPrimary: Colors.black,
          onSecondary: Colors.black,
          onSurface: Colors.white,
          onError: Colors.black,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: highContrastDarkSystemUiOverlay,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
          iconTheme: IconThemeData(color: brandReed),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.black,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
            side: const BorderSide(color: Colors.white, width: 1.5),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.black,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: Colors.white, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: Colors.white, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: brandReed, width: 2.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: errorLight, width: 2),
          ),
        ),
        chipTheme: expressiveChipTheme(
          background: Colors.black,
          selectedFill: brandReed.withValues(alpha: 0.28),
          label: Colors.white,
          selectedLabel: brandReed,
          outline: Colors.white,
          highContrast: true,
        ),
        segmentedButtonTheme: expressiveSegmentedTheme(
          selectedFill: brandReed.withValues(alpha: 0.28),
          selectedForeground: brandReed,
          foreground: Colors.white,
          outline: Colors.white,
          highContrast: true,
        ),
        dividerTheme: const DividerThemeData(
          color: Colors.white54,
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
              TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          titleLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          titleMedium:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          titleSmall:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Color(0xFFE8E8F0)),
          bodySmall: TextStyle(color: Color(0xFFCCCCCC)),
          labelLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          labelMedium: TextStyle(color: Color(0xFFE8E8F0)),
          labelSmall: TextStyle(color: Color(0xFFCCCCCC)),
        ),
      );
}

// LEGACY SUPPORT
const primaryColor = TurnaTheme.primary;
