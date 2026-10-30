// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/core/theme.dart';

/// 彩色玻璃材质（ADR 0062）的契约测试。
///
/// 这组断言的目的不是复述实现，而是守住三条容易被后续调参破坏的性质：
/// 1. 玻璃再深也不能吃掉文字对比度 —— 淡彩玻璃是底色，不是装饰；
/// 2. 暖色相的 accent 当阴影必须被冷化 —— 否则白纸上出现黄橙光晕；
/// 3. 高对比模式下玻璃必须整体让位，不能有半玻璃态。
void main() {
  const accents = <Color>[
    TurnaTheme.glassFocus,
    TurnaTheme.glassContainer,
    TurnaTheme.glassAchievement,
    TurnaTheme.glassPending,
    TurnaTheme.glassDanger,
    TurnaTheme.glassNeutral,
  ];

  /// 取渐变最深处（alpha 最大）压在指定基面上的结果，作为最坏情况底色。
  Color worstCaseFill(
    BuildContext ctx,
    Color accent,
    GlassLevel level,
    Color base,
  ) {
    final gradient = TurnaTheme.glassFill(ctx, accent, level: level);
    final deepest = gradient.colors.last;
    // glassFill 返回的是已经 alphaBlend 过的实色；再叠一次到 base 上，
    // 保证 base 与主题实际画布一致（浅色纯白 / 深色 #161616）。
    return Color.alphaBlend(deepest, base);
  }

  group('淡彩玻璃上的文字对比度', () {
    testWidgets('浅色：正文与副文字都过 WCAG AA', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      for (final accent in accents) {
        for (final level in [GlassLevel.l1, GlassLevel.l2]) {
          final bg =
              worstCaseFill(ctx, accent, level, Colors.white);
          expect(
            TurnaTheme.contrastRatio(TurnaTheme.textPrimary, bg),
            greaterThanOrEqualTo(7.0),
            reason: 'textPrimary on $accent/$level 低于 7:1（bg=$bg）',
          );
          expect(
            TurnaTheme.contrastRatio(TurnaTheme.textSecondary, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'textSecondary on $accent/$level 低于 4.5:1（bg=$bg）',
          );
        }
      }
    });

    testWidgets('深色：正文与副文字都过 WCAG AA', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.darkTheme,
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final base = TurnaTheme.cardBg(ctx);
      for (final accent in accents) {
        for (final level in [GlassLevel.l1, GlassLevel.l2]) {
          final bg = worstCaseFill(ctx, accent, level, base);
          expect(
            TurnaTheme.contrastRatio(
              TurnaTheme.textSecondaryColor(ctx),
              bg,
            ),
            greaterThanOrEqualTo(4.5),
            reason: '深色 textSecondary on $accent/$level 低于 4.5:1',
          );
        }
      }
    });
  });

  group('暖色 accent 的阴影必须冷化', () {
    testWidgets('success / warning 投出的影子比原色更冷', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      for (final warm in const [
        TurnaTheme.success,
        TurnaTheme.warning,
        TurnaTheme.warmSand,
      ]) {
        final shadow = TurnaTheme.glassShadow(ctx, warm, level: GlassLevel.l1);
        expect(shadow, isNotEmpty);
        final hue = shadow.first.color;
        // 蓝/红比升高 = 向 brandNavy 靠。直接把暖色当阴影会得到相反的比值。
        expect(
          hue.b / hue.r,
          greaterThan(warm.b / warm.r),
          reason: '$warm 的阴影没有冷化，白纸上会出现黄橙光晕',
        );
      }
    });

    testWidgets('badge 层不投影', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        TurnaTheme.glassShadow(ctx, TurnaTheme.glassFocus,
            level: GlassLevel.badge),
        isEmpty,
      );
    });
  });

  group('高对比短路', () {
    test('四套主题的 GlassMode 注册正确', () {
      expect(
        TurnaTheme.lightTheme.extension<GlassMode>()?.enabled,
        isTrue,
      );
      expect(
        TurnaTheme.darkTheme.extension<GlassMode>()?.enabled,
        isTrue,
      );
      expect(
        TurnaTheme.highContrastLightTheme.extension<GlassMode>()?.enabled,
        isFalse,
      );
      expect(
        TurnaTheme.highContrastDarkTheme.extension<GlassMode>()?.enabled,
        isFalse,
      );
    });

    testWidgets('off 时退化为纯白平面 + 描边，无渐变无投影', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.highContrastLightTheme,
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(TurnaTheme.glassEnabled(ctx), isFalse);

      final decoration = TurnaTheme.glassDecoration(
        ctx,
        TurnaTheme.glassFocus,
        level: GlassLevel.l2,
      );
      expect(decoration.gradient, isNull, reason: '高对比不该有淡彩渐变');
      expect(decoration.boxShadow, isNull, reason: '高对比不该有投影');
      // 高对比退回普通卡：底色与描边都取主题，尺寸与无玻璃时完全一致。
      expect(decoration.color, TurnaTheme.cardBg(ctx));
      expect(decoration.border?.top.width, 1);
    });
  });

  group('单层渐变约束', () {
    testWidgets('glassFill 的 stops 长度与 colors 一致且不含半透明白底', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      for (final level in GlassLevel.values) {
        final g = TurnaTheme.glassFill(ctx, TurnaTheme.glassFocus, level: level);
        expect(g.colors.length, g.stops!.length);
        expect(g.colors.length, 3, reason: '预混高光后只需三个 stop');
        // 白高光已预混进 stop 色值，所以每个 stop 必须是不透明色 ——
        // 若出现 alpha < 1，说明有人退回了「两层半透明叠加」的写法，
        // AnimatedContainer 会因此无法插值。
        for (final c in g.colors) {
          expect(c.a, 1.0, reason: '$level 的 stop 含半透明色，无法在动画中插值');
        }
      }
    });
  });
}
