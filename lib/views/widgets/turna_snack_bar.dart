// Dart imports:
import 'dart:ui' show ImageFilter;

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/views/theme.dart';

/// Material 3 风格的高斯模糊磨砂玻璃悬浮气泡 SnackBar。
///
/// 视觉与交互契约：
/// 1. 不触底、不贴边（`behavior: SnackBarBehavior.floating`，四周带边距）；
/// 2. 悬浮胶囊/大圆角气泡形态（`radiusXLarge` = 20px）；
/// 3. 内置 `BackdropFilter` 高斯模糊磨砂玻璃效果（sigma = 16，与底部导航栏保持视觉一致）；
/// 4. 自动感知系统/无障碍配置（高对比度或减少动效时退化为纯色/半透无模糊卡片）。
class TurnaSnackBar {
  TurnaSnackBar._();

  /// 高斯模糊强度（与 [BottomNavigator.frostSigma] 保持一致）
  static const double frostSigma = 16.0;

  /// 构建带有高斯模糊磨砂玻璃质感的悬浮气泡 [SnackBar]。
  static SnackBar create({
    required BuildContext context,
    required String message,
    Widget? icon,
    SnackBarAction? action,
    EdgeInsetsGeometry? margin,
    Duration duration = const Duration(seconds: 3),
  }) {
    final a11y = context.read<AccessibilityProvider?>();
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        (a11y?.reducedMotion ?? false);
    final solidGlass =
        (a11y?.highContrast ?? false) || (a11y?.focusMode ?? false);

    final radius = BorderRadius.circular(TurnaTheme.radiusXLarge);
    final fill = solidGlass
        ? TurnaTheme.bottomNavBg(context)
        : TurnaTheme.floatingBarFill(context);

    final textStyle = TextStyle(
      color: TurnaTheme.textPrimaryColor(context),
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.35,
    );

    final cardContent = Row(
      children: [
        if (icon != null) ...[
          icon,
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(
            message,
            style: textStyle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: action.onPressed,
            child: Text(
              action.label,
              style: TextStyle(
                color: action.textColor ?? TurnaTheme.brandTeal,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ],
    );

    final bubbleSurface = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(
          color: solidGlass
              ? TurnaTheme.statCardBorder(context)
              : TurnaTheme.glassBorder(context),
          width: solidGlass ? 1.5 : 1.0,
        ),
        boxShadow: TurnaTheme.floatingBarShadow(context),
      ),
      child: cardContent,
    );

    final bubble = ClipRRect(
      borderRadius: radius,
      child: solidGlass || reduceMotion
          ? bubbleSurface
          : BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: frostSigma,
                sigmaY: frostSigma,
              ),
              child: bubbleSurface,
            ),
    );

    return SnackBar(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.zero,
      margin: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: duration,
      content: bubble,
    );
  }

  /// 便捷方法：弹出高斯模糊悬浮气泡提示。
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context,
    String message, {
    Widget? icon,
    SnackBarAction? action,
    EdgeInsetsGeometry? margin,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    return messenger.showSnackBar(
      create(
        context: context,
        message: message,
        icon: icon,
        action: action,
        margin: margin,
        duration: duration,
      ),
    );
  }
}

/// [BuildContext] 快捷扩展方法
extension TurnaSnackBarExtension on BuildContext {
  /// 弹出 Material 3 高斯模糊悬浮气泡
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showFrostedSnackBar(
    String message, {
    Widget? icon,
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 3),
  }) {
    return TurnaSnackBar.show(
      this,
      message,
      icon: icon,
      action: action,
      duration: duration,
    );
  }
}
