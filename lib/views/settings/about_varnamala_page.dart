// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:varnamala/views/theme.dart';

/// Dedicated About page for Varnamala.
///
/// Shows the app brand, version, feature highlights, credits, open-source
/// licenses, and external links. Navigated to via [Navigator.push] so it does
/// not require auto_route code generation.
class AboutVarnamalaPage extends StatelessWidget {
  const AboutVarnamalaPage({Key? key}) : super(key: key);

  static const String _upstreamUrl = 'https://github.com/rshrc/Varnamala';
  static const String _issuesUrl = 'https://github.com/rshrc/Varnamala/issues';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          'About Varnamala',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BrandHeader(),
            const SizedBox(height: 24),
            _sectionTitle(context, 'What is Varnamala', Icons.lightbulb_rounded),
            _AboutCard(
              child: Text(
                'Varnamala is a free, open-source language learning app focused '
                'on helping you build real vocabulary and grammar skills — one '
                'small step at a time. It keeps learning offline, distraction-free, '
                'and under your control.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: VarnamalaTheme.textSecondaryColor(context),
                    ),
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle(context, 'Highlights', Icons.auto_awesome_rounded),
            const Row(
              children: [
                Expanded(
                  child: _HighlightCard(
                    icon: Icons.cloud_off_rounded,
                    title: 'Offline first',
                    subtitle: 'Learn anywhere',
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _HighlightCard(
                    icon: Icons.psychology_rounded,
                    title: 'SRS review',
                    subtitle: 'Remember more',
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _HighlightCard(
                    icon: Icons.quiz_rounded,
                    title: '11 interactions',
                    subtitle: 'Practice all skills',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _sectionTitle(context, 'Links', Icons.link_rounded),
            _AboutCard(
              child: Column(
                children: [
                  _LinkTile(
                    icon: Icons.code_rounded,
                    title: 'Open source licenses',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Varnamala',
                      applicationVersion: _fallbackVersion,
                    ),
                  ),
                  Divider(
                    height: 1,
                    indent: 48,
                    color: VarnamalaTheme.dividerBg(context),
                  ),
                  _LinkTile(
                    icon: Icons.open_in_new_rounded,
                    title: 'Upstream project',
                    subtitle: 'github.com/rshrc/Varnamala',
                    onTap: () => _launchUrl(_upstreamUrl),
                  ),
                  Divider(
                    height: 1,
                    indent: 48,
                    color: VarnamalaTheme.dividerBg(context),
                  ),
                  _LinkTile(
                    icon: Icons.bug_report_rounded,
                    title: 'Report an issue',
                    subtitle: 'GitHub Issues',
                    onTap: () => _launchUrl(_issuesUrl),
                  ),
                  Divider(
                    height: 1,
                    indent: 48,
                    color: VarnamalaTheme.dividerBg(context),
                  ),
                  _LinkTile(
                    icon: Icons.share_rounded,
                    title: 'Share Varnamala',
                    onTap: () => _shareApp(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle(context, 'Credits', Icons.favorite_rounded),
            _AboutCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Original framework by Rishi Banerjee and the Varnamala '
                    'open-source community.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                          color: VarnamalaTheme.textSecondaryColor(context),
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Licensed under the GNU General Public License v3.0.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: VarnamalaTheme.textHintColor(context),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                '© Varnamala Plus',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: VarnamalaTheme.textHintColor(context),
                    ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: VarnamalaTheme.peacockTeal, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: VarnamalaTheme.textSecondary,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _shareApp(BuildContext context) async {
    const String text =
        'Check out Varnamala — a free, open-source language learning app! '
        'https://github.com/rshrc/Varnamala';
    await Share.share(text);
  }
}

const String _fallbackVersion = '1.0.0';

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? _fallbackVersion;
        final buildNumber = snapshot.data?.buildNumber ?? '';
        final displayVersion = buildNumber.isEmpty
            ? 'Version $version'
            : 'Version $version ($buildNumber)';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            gradient: VarnamalaTheme.peacockGradient,
            borderRadius: BorderRadius.all(
              Radius.circular(VarnamalaTheme.radiusXLarge),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: VarnamalaTheme.textOnPrimary.withValues(alpha: 0.15),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: VarnamalaTheme.textOnPrimary,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Varnamala',
                style: TextStyle(
                  color: VarnamalaTheme.textOnPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Learn languages, one step at a time.',
                style: TextStyle(
                  color: VarnamalaTheme.textOnPrimary.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: VarnamalaTheme.textOnPrimary.withValues(alpha: 0.15),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusRound),
                ),
                child: Text(
                  displayVersion,
                  style: const TextStyle(
                    color: VarnamalaTheme.textOnPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

class _AboutCard extends StatelessWidget {
  final Widget child;

  const _AboutCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
      ),
      child: child,
    );
  }
}

class _HighlightCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _HighlightCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: VarnamalaTheme.peacockTeal, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: VarnamalaTheme.textHintColor(context),
                ),
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _LinkTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusMedium),
                ),
                child: Icon(
                  icon,
                  color: VarnamalaTheme.peacockTeal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: VarnamalaTheme.textHintColor(context),
                            ),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: VarnamalaTheme.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
