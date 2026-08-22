// Flutter imports:
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/views/theme.dart';

/// ADR 0033 — Turna wetland/crane palette contract.
///
/// Drives the real [TurnaTheme] entry points (not a re-implementation) and
/// structurally asserts clay productization call sites in shipped sources.
void main() {
  group('Scheme A core hex contract', () {
    test('brand tokens match locked wetland contract', () {
      expect(TurnaTheme.brandNavy, const Color(0xFF19324A));
      expect(TurnaTheme.brandTeal, const Color(0xFF1F727E));
      expect(TurnaTheme.brandTealLight, const Color(0xFF2F7F8E));
      expect(TurnaTheme.brandTealDark, const Color(0xFF145A64));
      expect(TurnaTheme.brandSky, const Color(0xFF4A95A8));
      expect(TurnaTheme.brandReed, const Color(0xFF78C7B8));
      expect(TurnaTheme.anatolianClay, const Color(0xFFB85C3F));
      expect(TurnaTheme.warmSand, const Color(0xFFEAD9B8));
    });

    test('semantic aliases map to brand tokens', () {
      expect(TurnaTheme.primary, TurnaTheme.brandTeal);
      expect(TurnaTheme.primaryLight, TurnaTheme.brandTealLight);
      expect(TurnaTheme.primaryDark, TurnaTheme.brandTealDark);
      expect(TurnaTheme.secondary, TurnaTheme.anatolianClay);
      expect(TurnaTheme.secondaryLight, TurnaTheme.warmSand);
      expect(TurnaTheme.info, TurnaTheme.brandSky);
    });

    test('primary CTA gradient is teal → tealLight only', () {
      expect(TurnaTheme.buttonGradient.colors, [
        TurnaTheme.brandTeal,
        TurnaTheme.brandTealLight,
      ]);
      expect(TurnaTheme.brandPrimaryGradient.colors, [
        TurnaTheme.brandTeal,
        TurnaTheme.brandTealLight,
      ]);
      // Clay must not appear in the primary button gradient.
      expect(
        TurnaTheme.buttonGradient.colors.contains(TurnaTheme.anatolianClay),
        isFalse,
      );
    });
  });

  group('ColorScheme secondary / primary roles', () {
    test('light theme: primary teal, secondary clay, secondaryContainer sand',
        () {
      final cs = TurnaTheme.lightTheme.colorScheme;
      expect(cs.primary, TurnaTheme.brandTeal);
      expect(cs.secondary, TurnaTheme.anatolianClay);
      expect(cs.secondaryContainer, TurnaTheme.warmSand);
    });

    test('dark theme: primary teal, secondary clay', () {
      final cs = TurnaTheme.darkTheme.colorScheme;
      expect(cs.primary, TurnaTheme.brandTeal);
      expect(cs.secondary, TurnaTheme.anatolianClay);
    });

    test('elevated button theme stays teal primary (not clay)', () {
      final bg = TurnaTheme.lightTheme.elevatedButtonTheme.style
          ?.backgroundColor
          ?.resolve({});
      expect(bg, TurnaTheme.brandTeal);
      expect(bg, isNot(TurnaTheme.anatolianClay));
    });

    test('high-contrast secondary may deviate from clay (a11y first)', () {
      // Documented role boundary: HC does not have to use clay secondary.
      expect(
        TurnaTheme.highContrastLightTheme.colorScheme.secondary,
        TurnaTheme.primaryDark,
      );
      expect(
        TurnaTheme.highContrastDarkTheme.colorScheme.secondary,
        TurnaTheme.brandReed,
      );
      // Surfaces stay pure black/white.
      expect(
        TurnaTheme.highContrastLightTheme.scaffoldBackgroundColor,
        Colors.white,
      );
      expect(
        TurnaTheme.highContrastDarkTheme.scaffoldBackgroundColor,
        Colors.black,
      );
    });
  });

  group('System UI overlay (status / nav bar)', () {
    test('light overlay: white chrome + dark icons', () {
      final style = TurnaTheme.systemUiOverlayFor(
        brightness: Brightness.light,
      );
      expect(style.statusBarColor, Colors.white);
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.systemNavigationBarColor, Colors.white);
      expect(style.systemNavigationBarIconBrightness, Brightness.dark);
      expect(
        TurnaTheme.lightTheme.appBarTheme.systemOverlayStyle,
        TurnaTheme.lightSystemUiOverlay,
      );
    });

    test('dark overlay: darkAppBar chrome + light icons', () {
      final style = TurnaTheme.systemUiOverlayFor(
        brightness: Brightness.dark,
      );
      expect(style.statusBarColor, TurnaTheme.darkAppBar);
      expect(style.statusBarIconBrightness, Brightness.light);
      expect(style.systemNavigationBarColor, TurnaTheme.darkAppBar);
      expect(
        TurnaTheme.darkTheme.appBarTheme.systemOverlayStyle,
        TurnaTheme.darkSystemUiOverlay,
      );
    });

    test('high-contrast overlays use pure black/white surfaces', () {
      final lightHc = TurnaTheme.systemUiOverlayFor(
        brightness: Brightness.light,
        highContrast: true,
      );
      final darkHc = TurnaTheme.systemUiOverlayFor(
        brightness: Brightness.dark,
        highContrast: true,
      );
      expect(lightHc.statusBarColor, Colors.white);
      expect(darkHc.statusBarColor, Colors.black);
      expect(
        TurnaTheme.highContrastLightTheme.appBarTheme.systemOverlayStyle,
        TurnaTheme.highContrastLightSystemUiOverlay,
      );
      expect(
        TurnaTheme.highContrastDarkTheme.appBarTheme.systemOverlayStyle,
        TurnaTheme.highContrastDarkSystemUiOverlay,
      );
    });

    test('light theme ships expressive chip and segmented themes', () {
      final chips = TurnaTheme.lightTheme.chipTheme;
      expect(chips.selectedColor, isNotNull);
      expect(chips.shape, isA<StadiumBorder>());
      expect(TurnaTheme.lightTheme.segmentedButtonTheme.style, isNotNull);
    });

    test('overlay colors are never brandTeal or clay fills', () {
      for (final style in [
        TurnaTheme.lightSystemUiOverlay,
        TurnaTheme.darkSystemUiOverlay,
        TurnaTheme.highContrastLightSystemUiOverlay,
        TurnaTheme.highContrastDarkSystemUiOverlay,
      ]) {
        expect(style.statusBarColor, isNot(TurnaTheme.brandTeal));
        expect(style.statusBarColor, isNot(TurnaTheme.anatolianClay));
      }
    });

    test('Android colors.xml matches Flutter surface tokens', () {
      final colors =
          File('android/app/src/main/res/values/colors.xml').readAsStringSync();
      expect(colors.contains('turna_scaffold_light">#F3F8F7'), isTrue);
      expect(colors.contains('turna_appbar_light">#FFFFFF'), isTrue);
      expect(colors.contains('turna_scaffold_dark">#101B22'), isTrue);
      expect(colors.contains('turna_appbar_dark">#182832'), isTrue);
    });

    test('Android light styles wire statusBar to turna_appbar_light', () {
      final styles =
          File('android/app/src/main/res/values/styles.xml').readAsStringSync();
      expect(styles.contains('@color/turna_appbar_light'), isTrue);
      expect(styles.contains('windowLightStatusBar">true'), isTrue);
    });

    test('Android night styles wire statusBar to turna_appbar_dark', () {
      final styles = File('android/app/src/main/res/values-night/styles.xml')
          .readAsStringSync();
      expect(styles.contains('@color/turna_appbar_dark'), isTrue);
      expect(styles.contains('windowLightStatusBar">false'), isTrue);
    });
  });

  group('Contrast gates (shipped TurnaTheme.contrastRatio)', () {
    test('white on brandTeal meets 4.5:1 body text', () {
      final ratio = TurnaTheme.contrastRatio(
        TurnaTheme.textOnPrimary,
        TurnaTheme.brandTeal,
      );
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('clay on warmSand is at least large-text 3:1', () {
      final ratio = TurnaTheme.contrastRatio(
        TurnaTheme.anatolianClay,
        TurnaTheme.warmSand,
      );
      // Small pills use clay on soft tint; solid clay-on-sand for icons/text.
      expect(ratio, greaterThanOrEqualTo(3.0));
    });

    test('primaryCtaDecoration is teal gradient only', () {
      final dec = TurnaTheme.primaryCtaDecoration();
      expect(dec.gradient, TurnaTheme.buttonGradient);
      expect(
        (dec.gradient as LinearGradient).colors.contains(TurnaTheme.anatolianClay),
        isFalse,
      );
    });
  });

  group('Clay helpers', () {
    testWidgets('clayAccent and claySoftTint use anatolianClay', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: Builder(
            builder: (context) {
              expect(TurnaTheme.clayAccent(context), TurnaTheme.anatolianClay);
              expect(
                TurnaTheme.claySoftTint(context),
                TurnaTheme.softTint(context, TurnaTheme.anatolianClay),
              );
              expect(TurnaTheme.clayOnSandText(context), TurnaTheme.anatolianClay);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });

  group('Legacy color aliases retired from theme source', () {
    test('theme.dart defines no peacock* identifiers', () {
      final themeFile = File('lib/views/theme.dart');
      expect(themeFile.existsSync(), isTrue);
      final src = themeFile.readAsStringSync();
      // Match API identifiers only (not narrative docs outside this file).
      final alias = RegExp(
        r'\bpeacock(Deep|Teal|Cyan|Turquoise|Mint|Gradient)\b',
      );
      expect(alias.hasMatch(src), isFalse,
          reason: 'peacock* aliases must be deleted (ADR 0033)');
    });
  });

  group('Clay productization call sites (structural)', () {
    test('course tree complete/perfect uses anatolianClay', () {
      final src = File('lib/views/courses/course_tree.dart').readAsStringSync();
      expect(src.contains('TurnaTheme.anatolianClay'), isTrue);
      // Fully-complete unit and perfect pill path both reference clay.
      expect(
        RegExp(r'isFullyComplete[\s\S]{0,200}anatolianClay').hasMatch(src),
        isTrue,
      );
      expect(
        RegExp(r'isPerfect[\s\S]{0,200}anatolianClay').hasMatch(src),
        isTrue,
      );
    });

    test('profile learning stats XP accent uses clay', () {
      final src =
          File('lib/views/profile/widgets/learning_stats.dart').readAsStringSync();
      expect(src.contains('TurnaTheme.anatolianClay'), isTrue);
      expect(src.contains('profileXpToday'), isTrue);
    });

    test('about brand header strip uses clay and sand', () {
      final src =
          File('lib/views/settings/about_turna_page.dart').readAsStringSync();
      expect(src.contains('TurnaTheme.anatolianClay'), isTrue);
      expect(src.contains('TurnaTheme.warmSand'), isTrue);
    });

    test('play hub weak-words tile uses clay secondary accent', () {
      final src = File('lib/views/play/play_hub_screen.dart').readAsStringSync();
      expect(src.contains('TurnaTheme.anatolianClay'), isTrue);
      expect(src.contains('playWeakWordsTitle'), isTrue);
    });

    test('achievements surfaces use clay accent', () {
      final overviewSrc = File(
        'lib/views/profile/achievements/achievement_overview_header.dart',
      ).readAsStringSync();
      expect(overviewSrc.contains('TurnaTheme.anatolianClay'), isTrue);

      final profileSrc =
          File('lib/views/profile/profile_screen.dart').readAsStringSync();
      expect(profileSrc.contains('TurnaTheme.anatolianClay'), isTrue);
      expect(profileSrc.contains('profileAchievementsTitle'), isTrue);
    });

    test('key CTAs use primaryCtaDecoration (gradient teal)', () {
      for (final path in [
        'lib/views/splash/components/get_started_button.dart',
        'lib/views/lesson/components/interactions/interaction_renderer.dart',
        'lib/views/lesson/components/lesson_dialogs.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains('primaryCtaDecoration'),
          isTrue,
          reason: '$path should use primaryCtaDecoration',
        );
      }
    });
  });
}
