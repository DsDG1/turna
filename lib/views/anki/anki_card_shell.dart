// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/theme.dart';

/// Unified visual shell for WebView-backed Anki card surfaces - course HTML
/// cards, unified-review fidelity cards and the official preview all share
/// these rules (WEBVIEW-UX-2026-08 §9.1): 22dp radius, 1dp low-contrast
/// border, a light shadow in day mode; dark mode drops the shadow and
/// strengthens the border so the card edge stays visible without elevation.
///
/// The shell owns exactly one padding/cropping layer; callers must not nest
/// another rounded surface inside.
class AnkiWebViewCardShell extends StatelessWidget {
  final Widget child;

  const AnkiWebViewCardShell({super.key, required this.child});

  static BorderRadius get radius => BorderRadius.circular(22);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        // 这里**刻意不用玻璃**（ADR 0062 的例外）：外壳里装的是用户自己的
        // Anki notetype HTML，卡片原貌就是验收标准。加任何淡彩都会让用户
        // 的卡在边缘透出不属于它的色，深色下尤甚。要改材质先改这条注释。
        color: TurnaTheme.cardBg(context),
        borderRadius: radius,
        border: Border.all(
          color: dark
              ? TurnaTheme.statCardBorder(context).withValues(alpha: 0.9)
              : TurnaTheme.statCardBorder(context),
        ),
        boxShadow: dark
            ? const <BoxShadow>[]
            : <BoxShadow>[
                BoxShadow(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}
