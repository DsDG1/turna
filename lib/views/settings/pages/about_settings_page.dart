// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/application/settings/settings_destination.dart';
import 'package:turna/views/settings/pages/settings_category_body.dart';
import 'package:turna/views/settings/widgets/settings_about_section.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';

/// About category page (formal route: `/settings/about`).
@RoutePage()
class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: SettingsDestination.about.title,
      body: const SettingsCategoryBody(
        pageStorageKey: 'settings-about',
        child: SettingsAboutSection(),
      ),
    );
  }
}
