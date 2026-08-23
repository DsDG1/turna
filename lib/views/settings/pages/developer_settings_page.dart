// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/application/settings/settings_destination.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/settings/pages/settings_category_body.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/settings/widgets/settings_fun_section.dart';

/// Debug-only developer lab (formal route: `/settings/developer`).
///
/// The route is only registered in debug builds (see `routing.dart`), so
/// release/profile builds have neither the landing entry nor a reachable
/// deep link to it.
@RoutePage()
class DeveloperSettingsPage extends StatelessWidget {
  const DeveloperSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: SettingsDestination.developer.title,
      body: SettingsCategoryBody(
        pageStorageKey: 'settings-developer',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsFunSection(),
            _DeveloperLabSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Debug-only engine diagnostics: the Official-Anki internal import. Kept
/// reachable only through the developer lab so release builds never expose
/// a second import path that competes with the unified import flow.
class _DeveloperLabSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        SettingsSectionTitle(
          icon: Icons.bug_report_rounded,
          title: 'Engine 诊断',
        ),
        const SizedBox(height: 8),
        SettingsCard(
          children: [
            SettingsNavigationTile(
              icon: Icons.inventory_2_outlined,
              title: 'Official Anki 内部导入',
              subtitle: '内部构建：官方导入与正式复习（仅开发环境）',
              onTap: (ctx) =>
                  ctx.router.push(const OfficialAnkiInternalRoute()),
            ),
          ],
        ),
      ],
    );
  }
}
