// Flutter imports:
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/views/home/components/profile_app_bar.dart';
import 'package:turna/views/home/components/stat_app_bar.dart';
import 'package:turna/views/play/play_app_bar.dart';

/// The four root tabs must agree on chrome height.
///
/// Before this contract Learn carried a 60 dp bar (to fit its score / streak /
/// gems / due chip row) while Play, Profile and Settings silently fell back to
/// the framework's 56 dp. Switching tabs moved the title baseline by 4 dp, and
/// Settings — the only tab that owns its own [Scaffold] — additionally painted
/// its bar with `scaffoldBg` instead of the `AppBarTheme` fill, so its top edge
/// read as a different colour from the other three.
///
/// One token ([TurnaTheme.tabAppBarHeight]) and one fill (the theme's
/// `appBarTheme.backgroundColor`) now drive all four.
void main() {
  group('root tab app bar height', () {
    test('every tab bar measures the shared token', () {
      expect(
        const StatAppBar().preferredSize.height,
        TurnaTheme.tabAppBarHeight,
      );
      expect(
        const PlayAppBar().preferredSize.height,
        TurnaTheme.tabAppBarHeight,
      );
      expect(
        const ProfileAppBar().preferredSize.height,
        TurnaTheme.tabAppBarHeight,
      );
      // Settings has no PreferredSizeWidget: its bar lives inside the tab's
      // own Scaffold, so it is pinned by structure below.
      expect(TurnaTheme.tabAppBarHeight, 60);
    });

    test('no tab bar hardcodes its own height again', () {
      for (final path in const [
        'lib/views/home/components/stat_app_bar.dart',
        'lib/views/play/play_app_bar.dart',
        'lib/views/home/components/profile_app_bar.dart',
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

    test('settings landing bar uses the token and the theme fill', () {
      final src =
          File('lib/views/settings/settings_page.dart').readAsStringSync();
      expect(
        src.contains('toolbarHeight: TurnaTheme.tabAppBarHeight'),
        isTrue,
        reason: 'the Settings tab bar must not fall back to 56 dp',
      );
      // The AppBar block must not override its fill: the status-bar strip
      // above it is painted by the outer Scaffold, and a `scaffoldBg` fill
      // here is what made the Settings top edge read as a seam.
      final block = RegExp(r'appBar: AppBar\(([\s\S]{0,400}?)\n      \),')
          .firstMatch(src);
      expect(block, isNotNull, reason: 'settings appBar block moved');
      expect(
        block!.group(1)!.contains('backgroundColor'),
        isFalse,
        reason: 'Settings bar must inherit appBarTheme.backgroundColor so it '
            'matches the other tabs (and the status-bar strip above it)',
      );
    });

    test('settings title style matches the other tabs', () {
      final src =
          File('lib/views/settings/settings_page.dart').readAsStringSync();
      final play = File('lib/views/play/play_app_bar.dart').readAsStringSync();
      // Both must read their title style from textTheme.titleLarge — a
      // headlineSmall title rendered visibly heavier than the other tabs.
      for (final entry in {'settings': src, 'play': play}.entries) {
        expect(
          entry.value.contains('textTheme.titleLarge'),
          isTrue,
          reason: '${entry.key} tab title must use titleLarge',
        );
      }
      expect(
        src.contains('headlineSmall'),
        isFalse,
        reason: 'headlineSmall made the Settings title heavier than its peers',
      );
    });
  });
}
