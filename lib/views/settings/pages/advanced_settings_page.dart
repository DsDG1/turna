// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/application/settings/settings_destination.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/settings/pages/settings_category_body.dart';
import 'package:turna/views/settings/widgets/settings_advanced_section.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';

/// Advanced hub page (formal route: `/settings/advanced`). The
/// legacy-compatibility sub-page is its own route (`/settings/advanced/
/// legacy`) — pushed via [onOpenLegacy], never an in-page anchor enum.
@RoutePage()
class AdvancedSettingsPage extends StatelessWidget {
  const AdvancedSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: SettingsDestination.advanced.title,
      body: SettingsCategoryBody(
        pageStorageKey: 'settings-advanced',
        child: SettingsAdvancedSection(
          onOpenLegacy: () =>
              context.router.push(const LegacyCompatibilityRoute()),
        ),
      ),
    );
  }
}

/// Legacy compatibility sub-page of Advanced (formal route:
/// `/settings/advanced/legacy`).
@RoutePage()
class LegacyCompatibilityPage extends StatelessWidget {
  const LegacyCompatibilityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: '旧版与兼容性',
      body: SettingsCategoryBody(
        pageStorageKey: 'settings-advanced-legacy',
        child: SettingsAdvancedSection(showLegacy: true),
      ),
    );
  }
}
