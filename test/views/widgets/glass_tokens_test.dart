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
        for (final level in [
          GlassLevel.l1,
          GlassLevel.l2,
          GlassLevel.l1Quiet,
        ]) {
          final bg = worstCaseFill(ctx, accent, level, Colors.white);
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
        for (final level in [
          GlassLevel.l1,
          GlassLevel.l2,
          GlassLevel.l1Quiet,
        ]) {
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
        final g =
            TurnaTheme.glassFill(ctx, TurnaTheme.glassFocus, level: level);
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

  group('Card 默认底色', () {
    // Card 是单色容器，画不出渐变，所以它的 color 必须落在 glassSolid 的
    // 同一个色阶上，否则一页里会同时出现「纯白卡」和「淡彩卡」两代材质。
    // 这条断言把两者钉在一起：改 l1Subtle 的参数，Card 自动跟随；谁要是
    // 手改 CardThemeData.color 成别的值，这里立刻红。
    for (final mode in [Brightness.light, Brightness.dark]) {
      testWidgets('${mode.name} 下与 glassSolid 同源', (tester) async {
        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            theme: mode == Brightness.light
                ? TurnaTheme.lightTheme
                : TurnaTheme.darkTheme,
            home: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final solid = TurnaTheme.glassSolid(
          ctx,
          TurnaTheme.glassNeutral,
          level: GlassLevel.l1Subtle,
        );
        final card = Theme.of(ctx).cardTheme.color;
        expect(card, solid, reason: 'Card 底色与玻璃实面漂移了');
      });
    }
  });

  group('弱化档 l1Quiet（ADR 0063）', () {
    // l1Quiet 的全部意图就是「淡彩不动，只削高光与投影」。这三条把意图钉成
    // 可执行契约：谁要是顺手把淡彩也降了（中性灰在白底上会直接消失，
    // 见 theme.dart 里 l1Subtle 的注释），或把削掉的量又加回来，这里立刻红。
    final quiet = TurnaTheme.glassSpec(GlassLevel.l1Quiet);
    final subtle = TurnaTheme.glassSpec(GlassLevel.l1Subtle);

    test('淡彩浓度与 l1Subtle 完全同档', () {
      expect(quiet.tintStart, subtle.tintStart);
      expect(quiet.tintEnd, subtle.tintEnd);
      expect(quiet.darkTintStart, subtle.darkTintStart);
      expect(quiet.darkTintEnd, subtle.darkTintEnd);
      expect(quiet.darkBase, subtle.darkBase);
    });

    test('高光与投影都弱于 l1Subtle', () {
      expect(quiet.sheen, lessThan(subtle.sheen));
      expect(quiet.nearAlpha, lessThan(subtle.nearAlpha));
      expect(quiet.farAlpha, lessThan(subtle.farAlpha));
      expect(quiet.darkSheen, lessThan(subtle.darkSheen));
    });

    test('深色两层黑投影按档位取值，不是写死', () {
      // 深色下黑投影投在近黑画布上几乎看不见，但仍然必须分档 —— 否则
      // l1Quiet 在深色下拿到的还是 l1Subtle 那副投影，弱化只做了一半。
      expect(quiet.darkNearAlpha, lessThan(subtle.darkNearAlpha));
      expect(quiet.darkFarAlpha, lessThan(subtle.darkFarAlpha));
      // 其余档位保持既有数值，输出必须逐像素不变。
      for (final level in [GlassLevel.l1, GlassLevel.l1Subtle, GlassLevel.l2]) {
        final spec = TurnaTheme.glassSpec(level);
        expect(spec.darkNearAlpha, 0.18);
        expect(spec.darkFarAlpha, 0.30);
      }
    });

    testWidgets('与 l1Subtle 落在同一色阶（Card 契约不破）', (tester) async {
      for (final mode in [Brightness.light, Brightness.dark]) {
        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            theme: mode == Brightness.light
                ? TurnaTheme.lightTheme
                : TurnaTheme.darkTheme,
            home: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final quietSolid = TurnaTheme.glassSolid(
          ctx,
          TurnaTheme.glassNeutral,
          level: GlassLevel.l1Quiet,
        );
        expect(
          quietSolid,
          TurnaTheme.glassSolid(
            ctx,
            TurnaTheme.glassNeutral,
            level: GlassLevel.l1Subtle,
          ),
          reason: '${mode.name} 下 l1Quiet 与 l1Subtle 脱开了色阶',
        );
        expect(
          Theme.of(ctx).cardTheme.color,
          quietSolid,
          reason: '${mode.name} 下 Card 底色与 l1Quiet 实面漂移了',
        );
      }
    });
  });

  group('彩度系数 glassChroma（ADR 0065）', () {
    testWidgets('玻璃底比未降彩的同浓度罩染更灰，浓度表不动', (tester) async {
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

      // 浓度表是 ADR 0063 的地板，降彩不得顺手改 alpha。
      expect(TurnaTheme.glassChroma, lessThan(1));
      expect(
        TurnaTheme.glassSpec(GlassLevel.l1Quiet).tintEnd,
        TurnaTheme.glassSpec(GlassLevel.l1Subtle).tintEnd,
      );

      final tintEnd = TurnaTheme.glassSpec(GlassLevel.l1).tintEnd;
      for (final accent in const [
        TurnaTheme.warning,
        TurnaTheme.glassFocus,
      ]) {
        final calmed =
            TurnaTheme.glassFill(ctx, accent, level: GlassLevel.l1).colors.last;
        final raw = Color.alphaBlend(
          accent.withValues(alpha: tintEnd),
          Colors.white,
        );
        expect(
          HSLColor.fromColor(calmed).saturation,
          lessThan(HSLColor.fromColor(raw).saturation),
          reason: '$accent 的玻璃底没有降彩',
        );
      }

      final stroke = TurnaTheme.glassStroke(
        ctx,
        TurnaTheme.warning,
        level: GlassLevel.l1,
      );
      expect(
        HSLColor.fromColor(stroke).saturation,
        lessThan(HSLColor.fromColor(TurnaTheme.warning).saturation),
        reason: '描边仍是未降彩的 accent',
      );

      final shadow =
          TurnaTheme.glassShadow(ctx, TurnaTheme.warning).first.color;
      final cooled = Color.lerp(
        TurnaTheme.warning,
        TurnaTheme.brandNavy,
        TurnaTheme.glassShadowCooling,
      )!
          .withValues(
        alpha: TurnaTheme.glassSpec(GlassLevel.l1).nearAlpha,
      );
      expect(shadow, cooled, reason: '投影冷却比例漂移了');
    });
  });

  group('按钮族', () {
    // 高对比曾漏覆盖按钮：copyWith 只换了 colorScheme.primary，按钮仍是硬编码
    // 的亮 teal。HC light 的对比因此比它自己的 primary 低一档，HC dark 更糟
    // （primary 已是 brandReed，按钮还是暗青）。这组断言把四套都钉住。
    Color? filledBg(ThemeData t) =>
        t.filledButtonTheme.style?.backgroundColor?.resolve(<WidgetState>{});
    Color? outlinedFg(ThemeData t) =>
        t.outlinedButtonTheme.style?.foregroundColor?.resolve(<WidgetState>{});
    Color? fabBg(ThemeData t) => t.floatingActionButtonTheme.backgroundColor;

    test('亮色与深色的实心按钮走 brandTeal', () {
      for (final t in [TurnaTheme.lightTheme, TurnaTheme.darkTheme]) {
        expect(filledBg(t), TurnaTheme.brandTeal);
        expect(outlinedFg(t), TurnaTheme.brandTeal);
        expect(fabBg(t), TurnaTheme.brandTeal);
      }
    });

    test('高对比亮色走 primaryDark，不再沿用亮 teal', () {
      final t = TurnaTheme.highContrastLightTheme;
      expect(filledBg(t), TurnaTheme.primaryDark);
      expect(outlinedFg(t), TurnaTheme.primaryDark);
      expect(fabBg(t), TurnaTheme.primaryDark);
      expect(
        filledBg(t),
        isNot(TurnaTheme.brandTeal),
        reason: 'HC 亮色退回亮 teal，说明 copyWith 又漏了按钮族',
      );
    });

    test('高对比深色走 brandReed', () {
      final t = TurnaTheme.highContrastDarkTheme;
      expect(filledBg(t), TurnaTheme.brandReed);
      expect(outlinedFg(t), TurnaTheme.brandReed);
      expect(fabBg(t), TurnaTheme.brandReed);
    });

    test('实心按钮的文字色与底色不撞（HC 深色是黑字 on 亮青）', () {
      final hcDark = TurnaTheme.highContrastDarkTheme;
      final fg = hcDark.filledButtonTheme.style?.foregroundColor
          ?.resolve(<WidgetState>{});
      expect(fg, Colors.black);
      expect(TurnaTheme.contrastRatio(fg!, TurnaTheme.brandReed),
          greaterThanOrEqualTo(7.0));
    });
  });

  group('ListTile 主题', () {
    // 15 处裸 ListTile / CheckboxListTile / SwitchListTile 散在 12 个文件，
    // 靠全局主题收口。这里钉住四套主题都注册过，防止以后被误删 ——
    // 删掉不会有编译错误，只会让 4 处未显式配色的 leading 图标悄悄退回
    // 默认的 onSurfaceVariant。
    test('四套主题都注册了 contentPadding 与 iconColor', () {
      final themes = <String, ThemeData>{
        'light': TurnaTheme.lightTheme,
        'dark': TurnaTheme.darkTheme,
        'hcLight': TurnaTheme.highContrastLightTheme,
        'hcDark': TurnaTheme.highContrastDarkTheme,
      };

      for (final entry in themes.entries) {
        final tile = entry.value.listTileTheme;
        expect(
          tile.contentPadding,
          const EdgeInsets.symmetric(horizontal: 16),
          reason: '${entry.key} 的 ListTile 缩进没注册',
        );
        expect(tile.iconColor, isNotNull, reason: '${entry.key} 缺 iconColor');
      }
    });

    // 刻意留空两项：填了会切断 textTheme 的继承，并盖掉调用方自己传的
    // style（15 处里有 6 处显式传了 title/subtitle 的 style）。
    // 这条断言守的是那个决定，而不是「代码现在长这样」。
    test('不覆盖 title/subtitle 文字样式', () {
      for (final t in [
        TurnaTheme.lightTheme,
        TurnaTheme.darkTheme,
        TurnaTheme.highContrastLightTheme,
        TurnaTheme.highContrastDarkTheme,
      ]) {
        expect(t.listTileTheme.titleTextStyle, isNull);
        expect(t.listTileTheme.subtitleTextStyle, isNull);
      }
    });
  });
}
