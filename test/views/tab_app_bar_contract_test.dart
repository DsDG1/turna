import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/home/components/learn_top_bar.dart';
import 'package:turna/views/home/components/tab_body_top_spacer.dart';

void main() {
  group('root tab app bar height', () {
    test('only Learn owns a real tab bar; page-title tabs use the spacer', () {
      expect(
        const LearnTopBar().preferredSize.height,
        TurnaTheme.tabAppBarHeight,
      );
      expect(const TabBodySpacer().preferredSize.height, isZero);
      expect(TurnaTheme.tabAppBarHeight, 60);
    });

    test('Play, Profile and Settings reserve no extra transparent bar', () {
      final src = File('lib/views/home/home_page.dart').readAsStringSync();
      expect(
        'const TabBodySpacer(),'.allMatches(src).length,
        3,
        reason: 'the three in-page-title tabs must share the status-bar spacer',
      );
      expect(src.contains('PlayAppBar'), isFalse);
      expect(File('lib/views/play/play_app_bar.dart').existsSync(), isFalse);

      final play = File('lib/views/play/play_hub_page.dart').readAsStringSync();
      final profile =
          File('lib/views/profile/profile_page.dart').readAsStringSync();
      final settings =
          File('lib/views/settings/settings_page.dart').readAsStringSync();
      for (final source in [play, profile, settings]) {
        expect(
          source.contains('AppSpacing.sm + 4'),
          isTrue,
          reason: 'in-page titles must share the same top inset',
        );
      }
    });

    test('the real Learn bar does not hardcode its own height', () {
      for (final path in const [
        'lib/views/home/components/learn_top_bar.dart',
        'lib/views/home/components/light_top_bar.dart',
      ]) {
        final src = File(path).readAsStringSync();
        final heights =
            RegExp(r'Size\.fromHeight\(([^)]*)\)').allMatches(src).toList();
        expect(heights, isNotEmpty, reason: '$path lost its preferredSize');
        for (final m in heights) {
          expect(
            m.group(1)!.trim(),
            'TurnaTheme.tabAppBarHeight',
            reason: '$path hardcodes an app bar height again',
          );
        }
      }
    });

    test('retired tab app bars stay deleted', () {
      expect(
        File('lib/views/home/components/profile_app_bar.dart').existsSync(),
        isFalse,
      );
      expect(
        File('lib/views/settings/settings_app_bar.dart').existsSync(),
        isFalse,
      );
      expect(
        File('lib/views/play/play_app_bar.dart').existsSync(),
        isFalse,
      );
    });

    test('settings landing opens with an in-page pageTitle', () {
      final src =
          File('lib/views/settings/settings_page.dart').readAsStringSync();
      expect(src.contains('appBar:'), isFalse);
      expect(src.contains('AppTextStyles.pageTitle'), isTrue);
    });

    test('settings title style matches the other tabs', () {
      final src =
          File('lib/views/settings/settings_page.dart').readAsStringSync();
      expect(src.contains('headlineSmall'), isFalse);
    });
  });
}
