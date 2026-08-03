// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/settings/beginner_guide_page.dart';
import 'package:varnamala/views/settings/changelog_page.dart';
import 'package:varnamala/views/theme.dart';

/// Dedicated About page for Varnamala.
///
/// Three tabs in a single Scaffold:
///   - **关于** (`_AboutTab`): brand header, highlights, privacy, version,
///     links, credits. Same content as the legacy single-page About.
///   - **更新日志** (`ChangelogFromAsset`): reads `assets/changelog.md`
///     and renders release cards. One-tap copy from the AppBar action.
///   - **使用指南** (`QuickStartFromAsset`): reads `assets/quick_start.md`
///     and renders section cards.
///
/// Visual style mirrors the learning (course tree) page:
///   - mint gradient background (`courseTreeGradientFor`)
///   - white/dark cards with soft shadow + 1px border
///   - peacockTeal-tinted icon tiles and version pill
///   - section headers rendered as a short teal bar + title (UnitHeader rhythm)
class AboutVarnamalaPage extends StatelessWidget {
  const AboutVarnamalaPage({super.key});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _shareApp(BuildContext context) async {
    await Share.share(AppStrings.aboutShareText);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: VarnamalaTheme.scaffoldBg(context),
        appBar: AppBar(
          title: Text(
            AppStrings.aboutTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              color: VarnamalaTheme.scaffoldBg(context),
              child: TabBar(
                indicatorColor: VarnamalaTheme.peacockTeal,
                indicatorWeight: 3,
                labelColor: VarnamalaTheme.peacockTeal,
                unselectedLabelColor: VarnamalaTheme.textHintColor(context),
                labelStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                tabs: const [
                  Tab(text: '关于'),
                  Tab(text: '更新日志'),
                  Tab(text: '使用指南'),
                ],
              ),
            ),
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: VarnamalaTheme.courseTreeGradientFor(context),
          ),
          child: TabBarView(
            children: [
              _AboutTab(
                onLaunchUrl: _launchUrl,
                onShare: _shareApp,
              ),
              Builder(
                builder: (innerContext) {
                  final controller = DefaultTabController.of(innerContext);
                  return ChangelogFromAsset(
                    onCopyText: (text) async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (!innerContext.mounted) return;
                      ScaffoldMessenger.of(innerContext).showSnackBar(
                        SnackBar(
                          content: Text(AppStrings.changelogCopied),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                      controller.index = 0;
                    },
                  );
                },
              ),
              const SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: QuickStartFromAsset(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "关于"Tab 内容。原 AboutVarnamalaPage 主体内容抽到此处,
/// 顺序与样式不变,仅外层换为 Column(由 TabBarView 嵌入)。
class _AboutTab extends StatelessWidget {
  final Future<void> Function(String url) onLaunchUrl;
  final Future<void> Function(BuildContext) onShare;

  const _AboutTab({
    required this.onLaunchUrl,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandHeader(),
          const SizedBox(height: 20),
          _SectionHeader(text: AppStrings.aboutWhatIsTitle),
          const SizedBox(height: 10),
          _AboutCard(
            child: Text(
              AppStrings.aboutWhatIsBody,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                    color: VarnamalaTheme.textSecondaryColor(context),
                  ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader(text: AppStrings.aboutHighlightsTitle),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _HighlightCard(
                  icon: Icons.cloud_off_rounded,
                  title: AppStrings.aboutHighlightOfflineTitle,
                  subtitle: AppStrings.aboutHighlightOfflineSubtitle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HighlightCard(
                  icon: Icons.psychology_rounded,
                  title: AppStrings.aboutHighlightSrsTitle,
                  subtitle: AppStrings.aboutHighlightSrsSubtitle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HighlightCard(
                  icon: Icons.quiz_rounded,
                  title: AppStrings.aboutHighlightInteractionsTitle,
                  subtitle: AppStrings.aboutHighlightInteractionsSubtitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionHeader(text: AppStrings.aboutPrivacyTitle),
          const SizedBox(height: 10),
          _AboutCard(
            child: Text(
              AppStrings.aboutPrivacyBody,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                    color: VarnamalaTheme.textSecondaryColor(context),
                  ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader(text: AppStrings.aboutVersionTitle),
          const SizedBox(height: 10),
          const _VersionCard(),
          const SizedBox(height: 20),
          _SectionHeader(text: AppStrings.aboutLinksTitle),
          const SizedBox(height: 10),
          _AboutCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _LinkTile(
                  icon: Icons.code_rounded,
                  title: AppStrings.settingsOpenSourceLicenses,
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Varnamala',
                    applicationVersion: _fallbackVersion,
                  ),
                ),
                _LinkDivider(),
                _LinkTile(
                  icon: Icons.open_in_new_rounded,
                  title: AppStrings.aboutUpstreamTitle,
                  subtitle: AppStrings.aboutUpstreamSubtitle,
                  onTap: () => onLaunchUrl(
                    'https://github.com/rshrc/Varnamala',
                  ),
                ),
                _LinkDivider(),
                _LinkTile(
                  icon: Icons.bug_report_rounded,
                  title: AppStrings.aboutReportIssueTitle,
                  subtitle: AppStrings.aboutReportIssueSubtitle,
                  onTap: () => onLaunchUrl(
                    'https://github.com/rshrc/Varnamala/issues',
                  ),
                ),
                _LinkDivider(),
                _LinkTile(
                  icon: Icons.new_releases_rounded,
                  title: AppStrings.aboutViewReleasesTitle,
                  subtitle: AppStrings.aboutViewReleasesSubtitle,
                  onTap: () => onLaunchUrl(
                    'https://github.com/rshrc/Varnamala/releases',
                  ),
                ),
                _LinkDivider(),
                _LinkTile(
                  icon: Icons.share_rounded,
                  title: AppStrings.aboutShareTitle,
                  onTap: () => onShare(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader(text: AppStrings.aboutCreditsTitle),
          const SizedBox(height: 10),
          _AboutCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.aboutCreditsOriginal,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                        color: VarnamalaTheme.textSecondaryColor(context),
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  AppStrings.aboutCreditsFork,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                        color: VarnamalaTheme.textSecondaryColor(context),
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  AppStrings.aboutLicense,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: VarnamalaTheme.textHintColor(context),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              AppStrings.aboutCopyright(year.toString()),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: VarnamalaTheme.textHintColor(context),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

const String _fallbackVersion = '1.0.0';

/// Short bar + title, matching the learning page's `UnitHeader` rhythm.
class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: VarnamalaTheme.textSecondaryColor(context),
                ),
          ),
        ],
      ),
    );
  }
}

/// Compact brand area card (replaces the old `peacockGradient` banner).
///
/// Layout mirrors the section switcher on the learning page: tinted icon
/// tile on the left, brand + tagline in the middle, version pill on the
/// right. Adaptive to dark mode via `cardBg` / `softShadow`.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? _fallbackVersion;
        final buildNumber = snapshot.data?.buildNumber ?? '';
        final displayVersion = buildNumber.isEmpty
            ? AppStrings.aboutVersionLabel(version)
            : AppStrings.aboutVersionWithBuild(version, buildNumber);

        return Container(
          width: double.infinity,
          height: 84,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: VarnamalaTheme.cardBg(context),
            borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
            border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
            boxShadow: VarnamalaTheme.softShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: VarnamalaTheme.peacockTeal,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.aboutBrandName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: VarnamalaTheme.textPrimaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.aboutTagline,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: VarnamalaTheme.textSecondaryColor(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusRound),
                ),
                child: Text(
                  displayVersion,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: VarnamalaTheme.peacockTeal,
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

/// Standard content card: `cardBg` + 1px border + soft shadow + 16 radius.
/// Used for paragraph sections and the link list wrapper.
class _AboutCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _AboutCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
        boxShadow: VarnamalaTheme.softShadow,
      ),
      child: child,
    );
  }
}

/// Tinted-icon highlight card used in the 3-column "亮点" row.
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
        boxShadow: VarnamalaTheme.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
            ),
            child: Icon(
              icon,
              color: VarnamalaTheme.peacockTeal,
              size: 22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: VarnamalaTheme.textPrimaryColor(context),
                ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              Icon(
                Icons.chevron_right_rounded,
                color: VarnamalaTheme.textHint.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 64,
      endIndent: 16,
      color: VarnamalaTheme.dividerBg(context),
    );
  }
}

/// Shows the installed version + build and a link to the full offline changelog.
class _VersionCard extends StatelessWidget {
  const _VersionCard();

  @override
  Widget build(BuildContext context) {
    return _AboutCard(
      child: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          final version = snapshot.data?.version ?? _fallbackVersion;
          final buildNumber = snapshot.data?.buildNumber ?? '';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    AppStrings.aboutVersionShort(version),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (buildNumber.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        AppStrings.aboutVersionBuild(buildNumber),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: VarnamalaTheme.textHintColor(context),
                            ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                AppStrings.aboutReleasesNote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: VarnamalaTheme.textHintColor(context),
                    ),
              ),
              const SizedBox(height: 8),
              _LinkTile(
                icon: Icons.history_edu_rounded,
                title: AppStrings.aboutOpenChangelog,
                subtitle: AppStrings.aboutOpenChangelogSubtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChangelogPage(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
