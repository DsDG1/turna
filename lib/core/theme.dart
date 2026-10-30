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
///
/// **Dark mode is neutral black, not tinted.** The night background stack is a
/// pure black → neutral-grey ramp ([darkScaffold] `#000000`, [darkAppBar]
/// `#0F0F0F`, cards `#141414`, elevated `#1E1E1E`, rules `#2A2A2A`). Brand hue
/// is carried by accents only. Do **not** reintroduce green-tinted surfaces
/// (`#0F2119` / `#152B21` / `#12261C` / `#1B3529` / `#2C453A` are retired);
/// a tinted page fill makes every screen read as a different colour family.
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
  static const Color successDark = Color(0xFFE5C235);
  static const Color warning = Color(0xFFFF9F43);
  static const Color info = brandSky;

  // JEWEL TONES - distinct accents for feature surfaces (e.g. AI).
  static const Color amethystLeague = Color(0xFF9B59B6);

  // BACKGROUND COLORS
  static const Color background = Colors.white;
  static const Color surface = Colors.white;
  static const Color scaffoldBackground = Colors.white;
  static const Color cardBackground = Colors.white;
  static const Color divider = Color(0xFFE5E7E5);

  /// Dark scaffold / window chrome (≡ Android `turna_scaffold_dark`).
  ///
  /// Neutral black — dark mode carries **no colour hue** in its background
  /// stack. Brand colour lives in accents (teal / clay), never in the page
  /// fill, so night mode reads as black rather than as a green-tinted theme.
  static const Color darkScaffold = Color(0xFF000000);

  /// Dark AppBar / status bar surface (≡ Android `turna_appbar_dark`).
  ///
  /// One neutral step above [darkScaffold] so the bar still separates from
  /// the page without reintroducing a hue.
  static const Color darkAppBar = Color(0xFF0F0F0F);

  /// 深色副文字 / 弱提示：**中性冷灰，不带绿**。
  ///
  /// 旧值 `#B9CCC0` / `#84998C` 是「墨绿深色」时代的化石，和本文件头
  /// 「Dark mode is neutral black」直接冲突 —— 深色底上泛绿的灰字会让
  /// 每个页面读起来像另一个配色家族。这两个常量是深色文字的唯一真源，
  /// `_buildDarkTheme` 里的 textTheme / chipTheme / segmentedButtonTheme /
  /// bottomNavigationBarTheme 全部引用它们，不要再写字面量。
  static const Color darkTextSecondary = Color(0xFFA7B2B8);
  static const Color darkTextHint = Color(0xFF79858C);

  // TEXT COLORS
  static const Color textPrimary = Color(0xFF1C2730);
  static const Color textSecondary = Color(0xFF52616B);
  static const Color textHint = Color(0xFF9CA3AF);
  static const Color textOnPrimary = Colors.white;
  static const Color textOnSecondary = Colors.white;

  // LEAGUE COLORS (Jewel Tones)
  static const Color leagueBronze = Color(0xFFCD7F32);
  static const Color leagueGold = Color(0xFFFFD700);
  static const Color leagueAmethyst = Color(0xFF9B59B6);
  static const Color leagueRuby = Color(0xFFE74C3C);
  static const Color leagueEmerald = Color(0xFF27AE60);
  static const Color leagueDiamond = Color(0xFF3498DB);

  // GRADIENTS
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandNavy, brandTeal, brandSky],
  );

  /// L0 画布底色（ADR 0062）。
  ///
  /// 历史上这里是「湿地晨光」的三档渐变（`#FFFFFF → #FAFBFA → #F6F8F6`），
  /// 属于上一代「彩色背景 + 磨砂白卡」模型：白卡靠背景色透出来。
  ///
  /// 本代玻璃是「白纸上的彩色玻璃片」，颜色由玻璃自己发、影子投在白纸上。
  /// 背景一旦带色，卡面淡彩就失去参照。所以这里退化成纯白，**只保留
  /// LinearGradient 类型**（调用方按 gradient 消费，换成 SolidColor 会
  /// 牵动 4 个页面的 decoration 写法）。
  static const LinearGradient courseTreeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
  );

  static LinearGradient courseTreeGradientFor(BuildContext context) =>
      _isDark(context)
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [darkScaffold, darkScaffold],
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

  /// Box decoration for primary CTAs (teal → tealLight). Never insert clay.
  static BoxDecoration primaryCtaDecoration({
    BorderRadius? borderRadius,
    bool elevated = true,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(radiusMedium);
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

  static List<BoxShadow> get buttonShadow => [
        BoxShadow(
          color: brandNavy.withValues(alpha: 0.22),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];

  // ---------------------------------------------------------------------------
  // ELEVATION TIERS — 做题页的三层语义高度
  // ---------------------------------------------------------------------------
  //
  // 深色分支**不能**复用浅色参数. 深色画布是纯黑 [darkScaffold], 而
  // [brandNavy] 阴影投在 #000 上等于不存在 —— 这正是"深色永远不够立体"的
  // 根因. 深色改由"卡面明度台阶 + 白色描边/光晕"表达高度, 阴影只留一层
  // 极弱白光做轮廓分离.
  //
  // 浅色仍是 navy 双层影 (远大近小), 模拟光照下的悬浮磨砂面.

  /// L3 状态外发光: 选中 / 正确 / 错误. accent 由调用方给.
  static List<BoxShadow> stateGlow(Color accent) => [
        BoxShadow(
          color: accent.withValues(alpha: 0.20),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];

  /// 做题页画布底色.
  ///
  /// 浅色刻意比白卡低一档: 页面与卡面都是纯白时, 阴影是唯一分离线索,
  /// 卡片读起来就是"平的". 深色沿用纯黑画布.
  static Color lessonCanvasBg(BuildContext context) =>
      _isDark(context) ? darkScaffold : const Color(0xFFF5F8F7);

  /// 选项条圆角 — 比主卡 (radiusLarge) 小一号, 层级一眼分得开.
  static const double radiusOption = 14.0;

  // BORDER RADIUS
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;
  static const double radiusRound = 100.0;

  // CHROME
  /// Height of the four root-tab app bars (Learn / Play / Profile / Settings).
  ///
  /// The tabs used to disagree — Learn carried a 60 dp bar to fit its chip
  /// row while the other three fell back to the framework's 56 dp, so the
  /// title baseline jumped when switching tabs. One token, four consumers.
  /// Sub-pages keep the default 56 dp; they are pushed routes, not peers.
  static const double tabAppBarHeight = 60.0;

  // SEMANTIC TINT TOKENS
  // Common alpha-blended fills & borders used across feature widgets.
  // Non-const because `withValues` is computed at runtime.
  static final Color tintLight = brandTeal.withValues(alpha: 0.06);
  static final Color tintSoft = brandTeal.withValues(alpha: 0.08);

  /// 浮起 chrome（AppBar / chip / snackbar / 胶囊导航）的 1px 白色高光描边。
  ///
  /// 这是**一代**玻璃的残留：靠一道白线把浮起面从背景里切出来。内容卡用的
  /// 是二代 [glassStroke]（同色相深边）。两者语义不同，不要合并 —— 白色
  /// 高光边压在淡彩卡面上会读作「描边缺失」。
  static Color glassBorder(BuildContext context) => _isDark(context)
      ? Colors.white.withValues(alpha: 0.15)
      : Colors.white.withValues(alpha: 0.50);

  // ---------------------------------------------------------------------------
  // COLORED GLASS MATERIAL（第二代，ADR 0062）
  // ---------------------------------------------------------------------------
  // 与上面第一代 glassSurface / glassHighlight / glassBorder 的区别：
  //
  //   一代：白霜半透明，透出**有色的背景**（frosted-white over tinted bg）。
  //   二代：白纸上的一片**彩色玻璃**，背景永远纯白，颜色由玻璃自己发、
  //        影子也取同色相投回白纸（tinted glass over white paper）。
  //
  // 两者物理模型相反，不可混用。一代的 glassBorder（白 50%）保留，
  // 它服务的是 AppBar / chip / snackbar 这类「浮起 chrome」，不是内容卡。
  //
  // 关键实现约束 —— 白高光**预混进单层 LinearGradient 的 stops**，而不是
  // 叠第二层 fill。理由：
  //   1. AnimatedContainer 只能插值单个 gradient；两层 fill 无法插值，
  //      InteractionOptionTile 的 180ms 状态切换会跳变（6 个 renderer 共用）。
  //   2. 物理等价：白高光叠加 = 该处 accent 更淡（浅色）/ 基面更亮（深色），
  //      两种都能预先算成具体 stop 色值。
  //   3. 少一层 DecoratedBox —— 全 app 数百张卡片各少一次合成。

  /// 白纸上的彩色玻璃：默认与表单页用的中性冷灰。
  static const Color glassNeutral = Color(0xFF8CA0AB);

  /// 色相分配：路径与焦点。
  static const Color glassFocus = brandTeal;

  /// 色相分配：容器。
  static const Color glassContainer = warmSand;

  /// 色相分配：完成 / 成就。
  static const Color glassAchievement = anatolianClay;

  /// 色相分配：待办（待复习）。
  static const Color glassPending = warning;

  /// 色相分配：危险（需加强）。
  static const Color glassDanger = error;

  /// 高对比 / 降级时是否仍绘制玻璃材质。
  ///
  /// 缺省 `true`：主题未注册 extension 时按玻璃走，不会静默退化成扁平卡。
  static bool glassEnabled(BuildContext context) =>
      Theme.of(context).extension<GlassMode>()?.enabled ?? true;

  /// 淡彩 + 白高光预混后的单层渐变。
  ///
  /// [scale] 缩放淡彩浓度，供 `SoftCard.tintAlpha` 这类既有强度参数映射
  /// （`tintAlpha / 0.10` 即 1.0 倍，向后兼容）。
  static LinearGradient glassFill(
    BuildContext context,
    Color accent, {
    GlassLevel level = GlassLevel.l1,
    double scale = 1.0,
  }) {
    final spec = _glassSpec(level);
    final isDark = _isDark(context);
    final base = isDark ? spec.darkBase : Colors.white;
    final tintStart = isDark ? spec.darkTintStart : spec.tintStart;
    final tintEnd = isDark ? spec.darkTintEnd : spec.tintEnd;
    final sheen = isDark ? spec.darkSheen : spec.sheen;
    final mid = tintStart + (tintEnd - tintStart) * spec.sheenStop;

    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        _glassMix(accent, tintStart * scale, sheen, base),
        _glassMix(accent, mid * scale, 0, base),
        _glassMix(accent, tintEnd * scale, 0, base),
      ],
      stops: [0.0, spec.sheenStop, 1.0],
    );
  }

  /// 同色相双层投影。
  ///
  /// 色相先向 [brandNavy] 降彩度 28%：直接把 `success #FFD93D` 或
  /// `warning #FF9F43` 当阴影色会投出一圈明显的黄橙光晕，白纸上尤其脏。
  /// 降彩度后仍保留色相辨识，但读作「影子」而不是「发光」。
  ///
  /// 铁律：所有层一律「纯垂直 offset + spreadRadius 恒为 0」。任何非零
  /// spread 都会改变阴影的圆角半径（= 卡片圆角 ± spread），与卡片自身轮廓
  /// 错位后，会在圆角外侧露出一圈尖角状痕迹。
  static List<BoxShadow> glassShadow(
    BuildContext context,
    Color accent, {
    GlassLevel level = GlassLevel.l1,
  }) {
    final spec = _glassSpec(level);
    if (spec.stroke == 0) return const <BoxShadow>[];

    if (_isDark(context)) {
      return [
        BoxShadow(
          color: Colors.white.withValues(alpha: spec.darkSheen * 0.8),
          blurRadius: 14,
          offset: const Offset(0, -3),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.30),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];
    }

    final hue = Color.lerp(accent, brandNavy, 0.28)!;
    return [
      BoxShadow(
        color: hue.withValues(alpha: spec.nearAlpha),
        blurRadius: spec.nearBlur,
        offset: Offset(0, spec.nearY),
      ),
      BoxShadow(
        color: hue.withValues(alpha: spec.farAlpha),
        blurRadius: spec.farBlur,
        offset: Offset(0, spec.farY),
      ),
    ];
  }

  /// 淡彩最深端的**不透明实色**。
  ///
  /// 用于「一张卡被拆成多个 Sliver 子项逐行拼合」的场景（单元卡头 + 课程行）：
  /// 上半用 [glassFill] 渐变，下半必须用这个实色接住渐变的最低点，否则
  /// 两段的渐变各自重新开始，接缝处会出现一道明显的横断。
  static Color glassSolid(
    BuildContext context,
    Color accent, {
    GlassLevel level = GlassLevel.l1,
    double scale = 1.0,
  }) {
    final spec = _glassSpec(level);
    final isDark = _isDark(context);
    final base = isDark ? spec.darkBase : Colors.white;
    final tintEnd = isDark ? spec.darkTintEnd : spec.tintEnd;
    return _glassMix(accent, tintEnd * scale, 0, base);
  }

  /// 1px 同色相描边。有色玻璃边缘因折射比中心更沉，所以用 accent 本色而非白。
  static Color glassStroke(
    BuildContext context,
    Color accent, {
    GlassLevel level = GlassLevel.l1,
  }) {
    final spec = _glassSpec(level);
    if (spec.stroke == 0) return Colors.transparent;
    final alpha = _isDark(context) ? spec.stroke + 0.02 : spec.stroke;
    return accent.withValues(alpha: alpha);
  }

  /// 一个 [BoxDecoration] 全给：渐变 + 描边 + 投影。
  ///
  /// [boxShadow] 传 `const <BoxShadow>[]` 表示按下收影（不是"用默认值"）。
  /// 高对比 / [GlassMode.off] 时退化为纯白/纯黑平面 + 1.5px 描边。
  static BoxDecoration glassDecoration(
    BuildContext context,
    Color accent, {
    GlassLevel level = GlassLevel.l1,
    BorderRadius? borderRadius,
    List<BoxShadow>? boxShadow,
    double scale = 1.0,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(radiusLarge);
    if (!glassEnabled(context)) {
      // 高对比 / 专注模式：退回「无玻璃的普通卡」，而不是画成黑白卡。
      // 黑白卡在 HC dark 下会和纯黑页面同色，边界反而消失；HC light 下
      // 又会把原来的灰描边换成一圈黑线，属于没被要求的视觉变化。
      // 用主题自身的 cardBg + dividerBg，尺寸与改造前完全一致（1px），
      // 这样 420×760 的 golden 不会被撑高半个像素。
      return BoxDecoration(
        color: cardBg(context),
        borderRadius: radius,
        border: Border.all(color: dividerBg(context), width: 1),
      );
    }
    return BoxDecoration(
      gradient: glassFill(context, accent, level: level, scale: scale),
      borderRadius: radius,
      border: Border.all(
        color: glassStroke(context, accent, level: level),
        width: 1,
      ),
      boxShadow: boxShadow ?? glassShadow(context, accent, level: level),
    );
  }

  /// 把淡彩罩到不透明基面上，再叠白高光。**不接受半透明白做底** —— 深色下
  /// 会在纯黑画布上糊成灰雾（见文件头「Dark mode is neutral black」）。
  static Color _glassMix(
    Color accent,
    double alpha,
    double sheen,
    Color base,
  ) {
    final tinted = Color.alphaBlend(
      accent.withValues(alpha: alpha.clamp(0.0, 1.0)),
      base,
    );
    if (sheen <= 0) return tinted;
    return Color.alphaBlend(
      Colors.white.withValues(alpha: sheen.clamp(0.0, 1.0)),
      tinted,
    );
  }

  static _GlassSpec _glassSpec(GlassLevel level) => switch (level) {
        GlassLevel.l1 => const _GlassSpec(
            tintStart: 0.09,
            tintEnd: 0.16,
            sheen: 0.34,
            sheenStop: 0.40,
            stroke: 0.26,
            nearAlpha: 0.16,
            nearBlur: 10,
            nearY: 6,
            farAlpha: 0.13,
            farBlur: 34,
            farY: 16,
            darkBase: Color(0xFF161616),
            darkTintStart: 0.10,
            darkTintEnd: 0.17,
            darkSheen: 0.06,
          ),
        GlassLevel.l1Subtle => const _GlassSpec(
            // 表单卡用中性灰 accent，灰的彩度天然低 —— 浓度必须比彩色的 L1
            // 更饱和一档才立得起来。0.05/0.09 实测在白底上等于消失。
            tintStart: 0.07,
            tintEnd: 0.13,
            sheen: 0.34,
            sheenStop: 0.40,
            stroke: 0.24,
            nearAlpha: 0.15,
            nearBlur: 9,
            nearY: 5,
            farAlpha: 0.11,
            farBlur: 28,
            farY: 14,
            darkBase: Color(0xFF141414),
            darkTintStart: 0.08,
            darkTintEnd: 0.14,
            darkSheen: 0.05,
          ),
        GlassLevel.l2 => const _GlassSpec(
            tintStart: 0.11,
            tintEnd: 0.19,
            sheen: 0.40,
            sheenStop: 0.42,
            stroke: 0.40,
            nearAlpha: 0.18,
            nearBlur: 10,
            nearY: 5,
            farAlpha: 0.12,
            farBlur: 22,
            farY: 12,
            darkBase: Color(0xFF1C1C1C),
            darkTintStart: 0.12,
            darkTintEnd: 0.21,
            darkSheen: 0.08,
          ),
        GlassLevel.badge => const _GlassSpec(
            tintStart: 0.13,
            tintEnd: 0.13,
            sheen: 0,
            sheenStop: 1.0,
            stroke: 0,
            nearAlpha: 0,
            nearBlur: 0,
            nearY: 0,
            farAlpha: 0,
            farBlur: 0,
            farY: 0,
            darkBase: Color(0xFF141414),
            darkTintStart: 0.20,
            darkTintEnd: 0.20,
            darkSheen: 0,
          ),
      };

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
              const Color(0xFF141414),
            )
          : Color.alphaBlend(
              accent.withValues(alpha: alpha),
              Colors.white,
            );

  /// 着色卡上的 accent 文字/图标色：浅色直接用 accent；深色向白色提亮
  /// 35%，保证 teal/cyan 这类深 accent 在暗底上可读。
  static Color accentOnCard(BuildContext context, Color accent) =>
      _isDark(context) ? Color.lerp(accent, Colors.white, 0.35)! : accent;

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
      _isDark(context) ? const Color(0xFF141414) : Colors.white;

  static Color dividerBg(BuildContext context) =>
      _isDark(context) ? const Color(0xFF2A2A2A) : divider;

  static Color textPrimaryColor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color textSecondaryColor(BuildContext context) =>
      _isDark(context) ? darkTextSecondary : textSecondary;

  static Color textHintColor(BuildContext context) =>
      _isDark(context) ? darkTextHint : textHint;

  static Color inputFillColor(BuildContext context) =>
      _isDark(context) ? const Color(0xFF121212) : const Color(0xFFF5F6F5);

  static Color statCardBorder(BuildContext context) =>
      _isDark(context) ? const Color(0xFF2A2A2A) : divider;

  static Color bottomNavBg(BuildContext context) =>
      _isDark(context) ? const Color(0xFF141414) : Colors.white;

  /// Translucent frosted fill for the floating home tab bar. Paired with the
  /// capsule's backdrop blur: transparent enough for the blur to read, opaque
  /// enough to keep labels legible over worst-case content scrolling
  /// underneath.
  static Color floatingBarFill(BuildContext context) {
    // ADR 0062：胶囊导航是 L2 浮起面 → 主色相的淡彩。
    // 仍然保持半透明（BackdropFilter 在它背后做真模糊），所以这里先把
    // 白与 teal 混成不透明淡青白，再整体降 alpha，而不是叠两层半透明。
    final tint = Color.alphaBlend(
      glassFocus.withValues(alpha: _isDark(context) ? 0.16 : 0.10),
      _isDark(context) ? const Color(0xFF1C1C1C) : Colors.white,
    );
    return tint.withValues(alpha: 0.72);
  }

  /// Single-layer drop under the floating tab capsule. 保持单层 —— 双层彩影
  /// 会把胶囊下方的 home indicator 染上一圈色，那个区域归系统。
  static List<BoxShadow> floatingBarShadow(BuildContext context) => [
        BoxShadow(
          color: _isDark(context)
              ? Colors.black.withValues(alpha: 0.28)
              : Color.lerp(glassFocus, brandNavy, 0.28)!
                  .withValues(alpha: 0.16),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];

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
      _isDark(context) ? const Color(0xFF1A1510) : const Color(0xFFFFF3E0);

  /// Tinted surface for success / safe-state banners (cache cleared,
  /// database intact, etc.). Dark variant is a low-alpha deep green.
  static Color successSurface(BuildContext context) =>
      _isDark(context) ? const Color(0xFF131A15) : const Color(0xFFE8F5E9);

  /// Tinted surface for danger / destructive-state banners (safe mode,
  /// critical alert, etc.). Dark variant is a low-alpha deep red.
  static Color dangerSurface(BuildContext context) =>
      _isDark(context) ? const Color(0xFF1A1212) : const Color(0xFFFFEBEE);

  /// Error text/icon color readable on the current surface: dark red on
  /// light fills, light red on dark fills.
  static Color errorOnSurface(BuildContext context) =>
      _isDark(context) ? errorLight : errorDark;

  // ---------------------------------------------------------------------------
  // CLAY / SAND HELPERS (secondary brand — restrained warm accents)
  // ---------------------------------------------------------------------------

  /// Solid clay accent (icons, small pills). Prefer over hard-coded hex.
  static Color clayAccent(BuildContext context) => anatolianClay;

  /// Soft clay tint for secondary soft-tint cards (Play Hub optional tile, etc.).
  static Color claySoftTint(BuildContext context) =>
      softTint(context, anatolianClay);

  /// Warm sand surface for brand strips / chip fills under clay accents.
  static Color clayOnSandFill(BuildContext context) =>
      _isDark(context) ? anatolianClay.withValues(alpha: 0.18) : warmSand;

  /// Readable clay (or navy if sand contrast is weak) on sand-like fills.
  static Color clayOnSandText(BuildContext context) => anatolianClay;

  // MATERIAL THEME DATA
  static final ThemeData lightTheme = _buildLightTheme();

  static ThemeData _buildLightTheme() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        extensions: const <ThemeExtension<dynamic>>[GlassMode.on],
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
          // styleFrom treats elevation as a base level (pressed: +6); pin all states flat.
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: textOnPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ).copyWith(elevation: const WidgetStatePropertyAll<double>(0)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: textOnPrimary,
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
        dialogTheme: DialogThemeData(
          backgroundColor: cardBackground,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F6F5),
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
          background: const Color(0xFFF5F6F5),
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
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXLarge),
            side: const BorderSide(color: Color(0x1F1F727E), width: 1),
          ),
          backgroundColor: const Color(0xF2FFFFFF),
          contentTextStyle: const TextStyle(
            color: textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          elevation: 4,
          insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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

  static final ThemeData darkTheme = _buildDarkTheme();

  static ThemeData _buildDarkTheme() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        extensions: const <ThemeExtension<dynamic>>[GlassMode.on],
        primaryColor: primary,
        scaffoldBackgroundColor: darkScaffold,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          primaryContainer: primaryLight,
          secondary: secondary,
          // 深色下 secondaryContainer 不能沿用 warmSand —— 配 onSecondary
          // 的白色是「白字压米黄」≈1.3:1，任何 M3 组件用到都不可读。
          // 换成一块中性深面，语义（次级容器）保留，可读性问题消失。
          secondaryContainer: Color(0xFF22302F),
          // surface 必须与 scaffoldBackgroundColor 同值：surfaceColor()
          // 直接返回 colorScheme.surface，两处不一致会让 Settings/AI 页
          // （#0F0F0F）和 Home/Play（#000000）之间出现一道灰阶跳变。
          surface: darkScaffold,
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
          color: const Color(0xFF141414),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          // styleFrom treats elevation as a base level (pressed: +6); pin all states flat.
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: textOnPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ).copyWith(elevation: const WidgetStatePropertyAll<double>(0)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: textOnPrimary,
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
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF141414),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF121212),
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
          unselectedItemColor: darkTextHint,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        chipTheme: expressiveChipTheme(
          background: const Color(0xFF121212),
          selectedFill: brandTeal.withValues(alpha: 0.28),
          label: darkTextSecondary,
          selectedLabel: brandReed,
          outline: const Color(0xFF2A2A2A),
        ),
        segmentedButtonTheme: expressiveSegmentedTheme(
          selectedFill: brandTeal.withValues(alpha: 0.28),
          selectedForeground: brandReed,
          foreground: darkTextSecondary,
          outline: const Color(0xFF2A2A2A),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: brandTealLight,
          linearTrackColor: Color(0xFF2A2A2A),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: brandTeal,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXLarge),
            side: const BorderSide(color: Color(0x3D78C7B8), width: 1),
          ),
          backgroundColor: const Color(0xF2141414),
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          elevation: 4,
          insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF2A2A2A),
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
              TextStyle(color: darkTextSecondary, fontWeight: FontWeight.w500),
          titleSmall:
              TextStyle(color: darkTextSecondary, fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: darkTextSecondary),
          bodySmall: TextStyle(color: darkTextHint),
          labelLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          labelMedium: TextStyle(color: darkTextSecondary),
          labelSmall: TextStyle(color: darkTextHint),
        ),
      );

  /// High-contrast variant of [lightTheme] for low-vision / sensory needs.
  ///
  /// Pure white surfaces, near-black text, stronger borders, and a heavier
  /// focus ring — derived from [lightTheme] so only the contrast-relevant
  /// tokens change.
  static final ThemeData highContrastLightTheme = _buildHighContrastLight();

  static ThemeData _buildHighContrastLight() => lightTheme.copyWith(
        extensions: const <ThemeExtension<dynamic>>[GlassMode.off],
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
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
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
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXLarge),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          backgroundColor: Colors.white,
          contentTextStyle: const TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          elevation: 6,
          insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
  static final ThemeData highContrastDarkTheme = _buildHighContrastDark();

  static ThemeData _buildHighContrastDark() => darkTheme.copyWith(
        extensions: const <ThemeExtension<dynamic>>[GlassMode.off],
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
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.black,
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
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXLarge),
            side: const BorderSide(color: Colors.white, width: 2),
          ),
          backgroundColor: Colors.black,
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          elevation: 6,
          insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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

/// 彩色玻璃材质的四个层级。
///
/// - [l1] 内容卡（章节 / 单元 / 课程卡）
/// - [l1Subtle] 表单卡（设置页等长列表，浓度降一档避免整屏发花）
/// - [l2] 浮起面（下一课行、吸顶条、胶囊导航）
/// - [badge] 徽章 / 标签（平涂，无描边无投影）
enum GlassLevel { l1, l1Subtle, l2, badge }

/// 高对比 / 降级模式下的玻璃开关。
///
/// 注册在 [ThemeData.extensions] 上；[TurnaTheme.glassEnabled] 读取它。
/// 缺省 `true` —— 没注册 extension 的主题按玻璃绘制，不会静默退化成扁平卡。
@immutable
class GlassMode extends ThemeExtension<GlassMode> {
  const GlassMode({required this.enabled});

  final bool enabled;

  static const GlassMode on = GlassMode(enabled: true);
  static const GlassMode off = GlassMode(enabled: false);

  @override
  GlassMode copyWith({bool? enabled}) =>
      GlassMode(enabled: enabled ?? this.enabled);

  /// 开关不可插值：半程越过 0.5 直接切换，避免中途出现「半玻璃」。
  @override
  GlassMode lerp(GlassMode? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

/// [TurnaTheme.glassFill] / [glassShadow] / [glassStroke] 的共用参数表。
class _GlassSpec {
  const _GlassSpec({
    required this.tintStart,
    required this.tintEnd,
    required this.sheen,
    required this.sheenStop,
    required this.stroke,
    required this.nearAlpha,
    required this.nearBlur,
    required this.nearY,
    required this.farAlpha,
    required this.farBlur,
    required this.farY,
    required this.darkBase,
    required this.darkTintStart,
    required this.darkTintEnd,
    required this.darkSheen,
  });

  /// 浅色：淡彩浓度起止。
  final double tintStart;
  final double tintEnd;

  /// 浅色：白高光峰值 alpha 与衰减到位的位置。
  final double sheen;
  final double sheenStop;

  /// 描边 alpha。`0` 表示该层无描边 / 无投影（badge）。
  final double stroke;

  /// 浅色：同色相投影近层（收边）与远层（弥散）。
  final double nearAlpha;
  final double nearBlur;
  final double nearY;
  final double farAlpha;
  final double farBlur;
  final double farY;

  /// 深色：淡彩罩染的不透明基面（对齐 surfaceL1Fill / surfaceL2Fill / cardBg）。
  final Color darkBase;
  final double darkTintStart;
  final double darkTintEnd;
  final double darkSheen;
}
