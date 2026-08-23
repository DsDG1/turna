// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Project imports:
import 'package:turna/application/anki_official/official_anki_license_notices.dart';
import 'package:turna/application/settings/app_build_info.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Cached once per process — About footer and license page share this.
Future<PackageInfo>? _packageInfoFuture;

Future<PackageInfo> _loadPackageInfo() =>
    _packageInfoFuture ??= PackageInfo.fromPlatform();

/// Cached once per process — the single version source for every Settings
/// surface (Plan §16.3): no hardcoded fallback, "未知版本" when unavailable.
Future<AppBuildInfo>? _buildInfoFuture;

Future<AppBuildInfo> _loadBuildInfo() =>
    _buildInfoFuture ??= AppBuildInfo.load();

class SettingsAboutSection extends StatelessWidget {
  const SettingsAboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        SettingsNavigationTile(
          icon: Icons.school_rounded,
          title: AppStrings.settingsAboutTurna,
          subtitle: '关于 Turna、隐私与更新日志',
          onTap: (context) => context.router.push(AboutTurnaRoute()),
        ),
        settingsTileDivider(context),
        SettingsNavigationTile(
          icon: Icons.shield_outlined,
          title: AppStrings.privacyDetailsEntry,
          subtitle: AppStrings.privacyDetailsEntrySubtitle,
          onTap: (context) => context.router.push(const PrivacyDetailsRoute()),
        ),
        settingsTileDivider(context),
        SettingsNavigationTile(
          icon: Icons.code_rounded,
          title: AppStrings.settingsOpenSourceLicenses,
          onTap: (context) async {
            final info = await _loadPackageInfo();
            if (!context.mounted) return;
            showTurnaLicensePage(
              context: context,
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
    return FutureBuilder<AppBuildInfo>(
      future: _loadBuildInfo(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final label = info == null
            ? AppStrings.settingsVersionFooter(AppBuildInfo.unknownVersion)
            : (info.buildNumber.isEmpty
                ? AppStrings.settingsVersionFooter(info.versionName)
                : AppStrings.settingsVersionFooterWithBuild(
                    info.versionName, info.buildNumber));
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
                  Icons.info_outline,
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
