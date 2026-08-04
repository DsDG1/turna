// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:package_info_plus/package_info_plus.dart';

// Project imports:
import 'package:turna/views/settings/about_turna_page.dart';
import 'package:turna/views/settings/beginner_guide_page.dart';
import 'package:turna/views/settings/changelog_page.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Cached once per process — About footer and license page share this.
Future<PackageInfo>? _packageInfoFuture;

Future<PackageInfo> _loadPackageInfo() =>
    _packageInfoFuture ??= PackageInfo.fromPlatform();

class SettingsAboutSection extends StatelessWidget {
  const SettingsAboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        SettingsNavigationTile(
          icon: Icons.menu_book_rounded,
          title: AppStrings.beginnerGuideEntry,
          subtitle: AppStrings.beginnerGuideEntrySubtitle,
          onTap: (context) => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const BeginnerGuidePage(),
            ),
          ),
        ),
        settingsTileDivider(context),
        SettingsNavigationTile(
          icon: Icons.school_rounded,
          title: AppStrings.settingsAboutTurna,
          onTap: (context) => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AboutTurnaPage(),
            ),
          ),
        ),
        settingsTileDivider(context),
        SettingsNavigationTile(
          icon: Icons.history_edu_rounded,
          title: AppStrings.changelogTitle,
          onTap: (context) => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ChangelogPage(),
            ),
          ),
        ),
        settingsTileDivider(context),
        SettingsNavigationTile(
          icon: Icons.code_rounded,
          title: AppStrings.settingsOpenSourceLicenses,
          onTap: (context) async {
            final info = await _loadPackageInfo();
            if (!context.mounted) return;
            showLicensePage(
              context: context,
              applicationName: 'Turna',
              applicationVersion: info.version,
            );
          },
        ),
        settingsTileDivider(context),
        const SettingsVersionFooter(),
      ],
    );
  }
}

class SettingsVersionFooter extends StatelessWidget {
  const SettingsVersionFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _loadPackageInfo(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '1.0.0';
        final build = snapshot.data?.buildNumber ?? '';
        final label = build.isEmpty
            ? AppStrings.settingsVersionFooter(version)
            : AppStrings.settingsVersionFooterWithBuild(version, build);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: TurnaTheme.brandTeal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: TurnaTheme.textHintColor(context),
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
