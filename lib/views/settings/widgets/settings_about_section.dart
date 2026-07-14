// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:package_info_plus/package_info_plus.dart';

// Project imports:
import 'package:varnamala/views/settings/about_varnamala_page.dart';
import 'package:varnamala/views/settings/widgets/settings_common.dart';
import 'package:varnamala/views/theme.dart';

class SettingsAboutSection extends StatelessWidget {
  const SettingsAboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        SettingsNavigationTile(
          icon: Icons.school_rounded,
          title: 'About Varnamala',
          onTap: (context) => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AboutVarnamalaPage(),
            ),
          ),
        ),
        settingsTileDivider(context),
        SettingsNavigationTile(
          icon: Icons.code_rounded,
          title: 'Open source licenses',
          onTap: (context) => showLicensePage(
            context: context,
            applicationName: 'Varnamala',
            applicationVersion: '1.0.0',
          ),
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
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '1.0.0';
        final build = snapshot.data?.buildNumber ?? '';
        final label =
            build.isEmpty ? 'Version $version' : 'Version $version ($build)';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: VarnamalaTheme.peacockTeal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: VarnamalaTheme.textHintColor(context),
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
