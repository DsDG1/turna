// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/application/settings/settings_destination.dart';
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
          children: const [
            SettingsFunSection(),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
