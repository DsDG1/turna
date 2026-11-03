// Flutter imports:
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/views/home/components/learn_top_bar.dart';
import 'package:turna/views/home/components/tab_body_top_spacer.dart';
import 'package:turna/views/play/play_app_bar.dart';

/// The four root tabs must agree on chrome height.
///
/// Before this contract Learn carried a 60 dp bar (to fit its score / streak /
/// gems / due chip row) while Play, Profile and Settings silently fell back to
/// the framework's 56 dp. Switching tabs moved the title baseline by 4 dp.
///
/// 湿地雾光之后：Learn 的 bar 是 LightTopBar 家族（[LearnTopBar]，同一
/// token，无状态胶囊）；Play 的标题在页内（R07），顶栏是同 token 的透明
/// 占位；Profile 与 Settings 的 Tab 级 AppBar 已退役（R15 / R16）——两页以
/// 页内 pageTitle 开篇，AppBar 槽位由 [TabBodySpacer] 只占状态栏条。
void main() {
  group('root tab app bar height', () {
    test('every real tab bar measures the shared token', () {
      expect(
        const LearnTopBar().preferredSize.height,
        TurnaTheme.tabAppBarHeight,
      );
      expect(
        const PlayAppBar().preferredSize.height,
        TurnaTheme.tabAppBarHeight,
      );
      // Profile / Settings own no Tab-level bar anymore: the spacer covers
      // only the status-bar strip (measured height comes from the Scaffold),
      // and each page opens with an in-page pageTitle instead.
      expect(const TabBodySpacer().preferredSize.height, isZero);
      expect(TurnaTheme.tabAppBarHeight, 60);
    });

    test('no tab bar hardcodes its own height again', () {
      for (final path in const [
        'lib/views/home/components/learn_top_bar.dart',
        'lib/views/home/components/light_top_bar.dart',
        'lib/views/play/play_app_bar.dart',
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
      // ProfileAppBar / SettingsAppBar retired in the R15 / R16 refresh;
      // neither file nor the class name may come back.
      expect(
        File('lib/views/home/components/profile_app_bar.dart').existsSync(),
        isFalse,
        reason: 'ProfileAppBar retired; profile opens with an in-page title',
      );
      expect(
        File('lib/views/settings/settings_app_bar.dart').existsSync(),
        isFalse,
        reason: 'SettingsAppBar retired; settings opens with an in-page title',
      );
    });

    test('settings landing opens with an in-page pageTitle', () {
      final src =
          File('lib/views/settings/settings_page.dart').readAsStringSync();
      // The Settings tab owns no AppBar: the outer HomePage slot is a
      // TabBodySpacer, and the page body starts with the pageTitle role.
      expect(
        src.contains('appBar:'),
        isFalse,
        reason: 'the Settings tab must not own its own AppBar anymore',
      );
      expect(
        src.contains('AppTextStyles.pageTitle'),
        isTrue,
        reason: 'settings landing must open with the pageTitle layout role',
      );
    });

    test('settings title style matches the other tabs', () {
      final src =
          File('lib/views/settings/settings_page.dart').readAsStringSync();
      // The in-page title must read from the 湿地雾光 layout roles instead of
      // an ad-hoc headline style that renders heavier than its peers.
      expect(
        src.contains('headlineSmall'),
        isFalse,
        reason: 'headlineSmall made the Settings title heavier than its peers',
      );
    });
  });
}
