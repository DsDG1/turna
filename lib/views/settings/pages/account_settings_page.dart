// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/application/settings/settings_destination.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/settings/pages/settings_category_body.dart';
import 'package:turna/views/settings/widgets/settings_account_section.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';

/// Account category page (formal route: `/settings/account`).
@RoutePage()
class AccountSettingsPage extends StatelessWidget {
  const AccountSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: SettingsDestination.account.title,
      body: SettingsCategoryBody(
        pageStorageKey: 'settings-account',
        child: SettingsAccountSection(
          onNavigateToData: () =>
              context.router.push(const DataBackupSettingsRoute()),
        ),
      ),
    );
  }
}
