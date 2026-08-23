// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/application/settings/settings_destination.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/theme.dart';

/// Settings landing page — ONLY the category list.
///
/// Every category (and second-level page) is a formal route pushed onto the
/// router (see [SettingsDestinationDescriptor.route]); pages are created
/// and destroyed with their route instead of being kept alive in an
/// Offstage stack. Scroll position of this list is preserved via its
/// [PageStorageKey]. Display metadata comes from the single
/// [SettingsDestinationDescriptor] extension — the parallel
/// title/icon/subtitle switches this page used to carry are gone.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// Landing groups (Plan 2 §5.2): person / learning experience / data &
  /// system / product. The developer lab is debug-only and never present in
  /// release/profile builds (Plan 2 §4.4).
  static List<(String, List<SettingsDestination>)> get _groups {
    return [
      (
        AppStrings.settingsGroupPersonal,
        [SettingsDestination.account],
      ),
      (
        AppStrings.settingsGroupLearning,
        [
          SettingsDestination.learning,
          SettingsDestination.appearanceAndSound,
          SettingsDestination.accessibility,
        ],
      ),
      (
        AppStrings.settingsGroupDataSystem,
        [SettingsDestination.dataAndBackup, SettingsDestination.advanced],
      ),
      (
        AppStrings.settingsGroupProduct,
        [SettingsDestination.about],
      ),
      if (kDebugMode)
        (
          AppStrings.settingsCategoryFunLab,
          [SettingsDestination.developer],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.surfaceColor(context),
      appBar: AppBar(
        backgroundColor: TurnaTheme.surfaceColor(context),
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.settings_rounded,
              color: TurnaTheme.brandTeal,
              size: 22,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                AppStrings.settingsTitle,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        key: const PageStorageKey<String>('settings-landing-list'),
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          0,
          0,
          0,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (groupTitle, destinations) in _groups) ...[
              SettingsSectionTitle(
                icon: destinations.first.icon,
                title: groupTitle,
              ),
              const SizedBox(height: 8),
              _categoryCard(context, destinations),
              const SizedBox(height: 20),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _categoryCard(
    BuildContext context,
    List<SettingsDestination> destinations,
  ) {
    return SettingsCard(
      children: [
        for (int i = 0; i < destinations.length; i++) ...[
          if (i > 0) settingsTileDivider(context),
          SettingsNavigationTile(
            key: ValueKey(destinations[i].name),
            icon: destinations[i].icon,
            title: destinations[i].title,
            subtitle: destinations[i].subtitle,
            onTap: (context) => context.router.push(destinations[i].route),
          ),
        ],
      ],
    );
  }
}
