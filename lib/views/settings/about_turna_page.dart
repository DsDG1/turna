// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:share_plus/share_plus.dart';

// Project imports:
import 'package:turna/application/anki_official/official_anki_license_notices.dart';
import 'package:turna/application/settings/app_build_info.dart';
import 'package:turna/application/settings/external_link_registry.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/settings/changelog_page.dart';
import 'package:turna/views/theme.dart';

/// Dedicated About page for Turna (Plan 2 §7.1).
///
/// Two tabs only:
///   - **关于** (`_AboutTab`): brand header, highlights, privacy, version,
///     registry-driven links, credits.
///   - **更新日志** (`ChangelogFromAsset`): offline changelog.
///
/// The former 使用指南 tab was removed with its asset/parser (dead resource
/// per Plan 2 §4.8). All external links resolve through
/// [ExternalLinkRegistry]: unconfigured links render disabled with a reason
/// instead of dead-tapping a guessed legacy URL, and launch failures offer a
/// copy-address fallback.
@RoutePage()
class AboutTurnaPage extends StatelessWidget {
  const AboutTurnaPage({super.key, this.buildInfo});

  /// Test seam; production resolves from PackageInfo.
  final AppBuildInfo? buildInfo;

  Future<void> _shareApp(BuildContext context) async {
    await Share.share(AppStrings.aboutShareText);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: TurnaTheme.scaffoldBg(context),
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
              color: TurnaTheme.scaffoldBg(context),
              child: TabBar(
                indicatorColor: TurnaTheme.brandTeal,
                indicatorWeight: 3,
                labelColor: TurnaTheme.brandTeal,
                unselectedLabelColor: TurnaTheme.textHintColor(context),
                labelStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                tabs: const [
                  Tab(text: '关于'),
                  Tab(text: '更新日志'),
                ],
              ),
            ),
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: TurnaTheme.courseTreeGradientFor(context),
          ),
          child: TabBarView(
            children: [
              _AboutTab(
                buildInfo: buildInfo,
                onShare: _shareApp,
              ),
              const ChangelogFromAsset(),
            ],
          ),
        ),
      ),
    );
  }
}

/// "关于"Tab 内容：品牌头、亮点、隐私、版本、外链（注册表驱动）、致谢。
class _AboutTab extends StatelessWidget {
  const _AboutTab({this.buildInfo, required this.onShare});

  final AppBuildInfo? buildInfo;

  /// Registry injection seam for widget tests (five launch states).
  final ExternalLinkRegistry linkRegistry = const ExternalLinkRegistry();

  final Future<void> Function(BuildContext) onShare;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BrandHeader(buildInfo: buildInfo),
          const SizedBox(height: 20),
          _SectionHeader(text: AppStrings.aboutWhatIsTitle),
          const SizedBox(height: 10),
          _AboutCard(
            child: Text(
              AppStrings.aboutWhatIsBody,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader(text: AppStrings.aboutHighlightsTitle),
          const SizedBox(height: 10),
          Builder(builder: (context) {
            // Wrap instead of a fixed 3-column Row: at 200% text scale or on
            // narrow screens the cards flow onto extra lines instead of
            // overflowing (Plan §14.4).
            final screenWidth = MediaQuery.sizeOf(context).width;
            final largeText =
                MediaQuery.textScalerOf(context).textScaleFactor > 1.3;
            final singleColumn = screenWidth < 560 || largeText;
            final cardWidth =
                singleColumn ? double.infinity : (screenWidth - 32 - 20) / 3;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final highlight in [
                  (
                    icon: Icons.cloud_off_rounded,
                    title: AppStrings.aboutHighlightOfflineTitle,
                    subtitle: AppStrings.aboutHighlightOfflineSubtitle,
                  ),
                  (
                    icon: Icons.psychology_rounded,
                    title: AppStrings.aboutHighlightSrsTitle,
                    subtitle: AppStrings.aboutHighlightSrsSubtitle,
                  ),
                  (
                    icon: Icons.quiz_rounded,
                    title: AppStrings.aboutHighlightInteractionsTitle,
                    subtitle: AppStrings.aboutHighlightInteractionsSubtitle,
                  ),
                ])
                  SizedBox(
                    width: cardWidth,
                    child: _HighlightCard(
                      icon: highlight.icon,
                      title: highlight.title,
                      subtitle: highlight.subtitle,
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: 20),
          _SectionHeader(text: AppStrings.aboutPrivacyTitle),
          const SizedBox(height: 10),
          _AboutCard(
            padding: EdgeInsets.zero,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
              child: InkWell(
                borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
                onTap: () => context.router.push(const PrivacyDetailsRoute()),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.aboutPrivacyBody,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                              color: TurnaTheme.textSecondaryColor(context),
                            ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            AppStrings.aboutPrivacyOpenDetails,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: TurnaTheme.brandTeal,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: TurnaTheme.brandTeal,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader(text: AppStrings.aboutVersionTitle),
          const SizedBox(height: 10),
          _VersionCard(buildInfo: buildInfo),
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
                  onTap: () => showTurnaLicensePage(
                    context: context,
                    applicationVersion: AppBuildInfo.unknownVersion,
                  ),
                ),
                _LinkDivider(),
                _ExternalLinkTile(
                  registry: linkRegistry,
                  id: ExternalLinkId.projectHome,
                  icon: Icons.open_in_new_rounded,
                  title: AppStrings.aboutUpstreamTitle,
                  configuredSubtitle: AppStrings.aboutUpstreamSubtitle,
                ),
                _LinkDivider(),
                _ExternalLinkTile(
                  registry: linkRegistry,
                  id: ExternalLinkId.issueTracker,
                  icon: Icons.bug_report_rounded,
                  title: AppStrings.aboutReportIssueTitle,
                  configuredSubtitle: AppStrings.aboutReportIssueSubtitle,
                ),
                _LinkDivider(),
                _ExternalLinkTile(
                  registry: linkRegistry,
                  id: ExternalLinkId.releaseNotes,
                  icon: Icons.new_releases_rounded,
                  title: AppStrings.aboutViewReleasesTitle,
                  configuredSubtitle: AppStrings.aboutViewReleasesSubtitle,
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
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              AppStrings.aboutLinksNotConfiguredNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.textHintColor(context),
                    height: 1.4,
                  ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader(text: AppStrings.aboutToolsTitle),
          const SizedBox(height: 10),
          _AboutCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _ExternalLinkTile(
                  registry: linkRegistry,
                  id: ExternalLinkId.guiPlatform,
                  icon: Icons.desktop_mac_rounded,
                  title: AppStrings.aboutToolGuiName,
                  configuredSubtitle: AppStrings.aboutToolGuiDesc,
                  isTool: true,
                ),
                _LinkDivider(),
                _ExternalLinkTile(
                  registry: linkRegistry,
                  id: ExternalLinkId.cliDocs,
                  icon: Icons.terminal_rounded,
                  title: AppStrings.aboutToolCliName,
                  configuredSubtitle: AppStrings.aboutToolCliDesc,
                  isTool: true,
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
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  AppStrings.aboutCreditsFork,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  AppStrings.aboutLicense,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TurnaTheme.textHintColor(context),
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
                    color: TurnaTheme.textHintColor(context),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

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
              color: TurnaTheme.brandTeal.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
          ),
        ],
      ),
    );
  }
}

/// Compact brand area card (replaces the old brand gradient banner).
///
/// Layout mirrors the section switcher on the learning page: tinted icon
/// tile on the left, brand + tagline in the middle, version pill on the
/// right. Adaptive to dark mode via `cardBg` / `softShadow`.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({this.buildInfo});

  final AppBuildInfo? buildInfo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppBuildInfo>(
      future: buildInfo != null ? Future.value(buildInfo) : AppBuildInfo.load(),
      builder: (context, snapshot) {
        // No hardcoded fallback number: unknown stays "未知版本".
        final info = snapshot.data ??
            const AppBuildInfo(
              versionName: AppBuildInfo.unknownVersion,
              buildNumber: '',
            );
        final displayVersion = info.buildNumber.isEmpty
            ? AppStrings.aboutVersionLabel(info.versionName)
            : AppStrings.aboutVersionWithBuild(
                info.versionName, info.buildNumber);

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: TurnaTheme.cardBg(context),
            borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            border: Border.all(color: TurnaTheme.statCardBorder(context)),
            boxShadow: TurnaTheme.softShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Clay + sand brand strip (visibility polish; keep strip thin).
              Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      TurnaTheme.anatolianClay,
                      TurnaTheme.warmSand.withValues(alpha: 0.95),
                    ],
                  ),
                ),
              ),
              // No fixed height: the brand block sizes itself so long
              // taglines wrap instead of clipping at large text scales
              // (Plan §14.4).
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: TurnaTheme.clayOnSandFill(context),
                        borderRadius:
                            BorderRadius.circular(TurnaTheme.radiusMedium),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: TurnaTheme.anatolianClay,
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
                              color: TurnaTheme.textPrimaryColor(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppStrings.aboutTagline,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: TurnaTheme.textSecondaryColor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(TurnaTheme.radiusRound),
                      ),
                      child: Text(
                        displayVersion,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: TurnaTheme.brandTeal,
                        ),
                      ),
                    ),
                  ],
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
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
        boxShadow: TurnaTheme.softShadow,
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
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
        boxShadow: TurnaTheme.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            ),
            child: Icon(
              icon,
              color: TurnaTheme.brandTeal,
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
                  color: TurnaTheme.textPrimaryColor(context),
                ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
          ),
        ],
      ),
    );
  }
}

/// Registry-driven external link row: disabled with a visible reason when the
/// URL is unconfigured (never a fake clickable link), otherwise launches via
/// [openExternalLink] which surfaces failures with a copy-address fallback.
class _ExternalLinkTile extends StatelessWidget {
  const _ExternalLinkTile({
    required this.registry,
    required this.id,
    required this.icon,
    required this.title,
    required this.configuredSubtitle,
    this.isTool = false,
  });

  final ExternalLinkRegistry registry;
  final ExternalLinkId id;
  final IconData icon;
  final String title;

  /// Subtitle shown when the link is configured.
  final String configuredSubtitle;

  /// Tool rows use the richer 40px-tile layout.
  final bool isTool;

  @override
  Widget build(BuildContext context) {
    final descriptor = registry.describe(id);
    final subtitle =
        descriptor.enabled ? configuredSubtitle : descriptor.unavailableReason;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: isTool ? 40 : 36,
            height: isTool ? 40 : 36,
            decoration: BoxDecoration(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            ),
            child: Icon(
              icon,
              color: descriptor.enabled
                  ? TurnaTheme.brandTeal
                  : TurnaTheme.textHintColor(context),
              size: isTool ? 22 : 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: descriptor.enabled
                            ? TurnaTheme.textPrimaryColor(context)
                            : TurnaTheme.textHintColor(context),
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TurnaTheme.textHintColor(context),
                      ),
                ),
              ],
            ),
          ),
          Icon(
            descriptor.enabled
                ? (isTool
                    ? Icons.arrow_forward_ios_rounded
                    : Icons.chevron_right_rounded)
                : Icons.lock_outline_rounded,
            size: isTool ? 14 : 20,
            color: TurnaTheme.textHint.withValues(alpha: 0.6),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        onTap: descriptor.enabled
            ? () => openExternalLink(context, id, registry: registry)
            // Disabled links still explain themselves on tap instead of
            // silently doing nothing.
            : () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(descriptor.unavailableReason),
                    behavior: SnackBarBehavior.floating,
                  ),
                ),
        child: body,
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  const _LinkTile({
    required this.icon,
    required this.title,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: Icon(
                  icon,
                  color: TurnaTheme.brandTeal,
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
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: TurnaTheme.textHint.withValues(alpha: 0.6),
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
      color: TurnaTheme.dividerBg(context),
    );
  }
}

/// Shows the installed version + build and a link to the full offline changelog.
class _VersionCard extends StatelessWidget {
  const _VersionCard({this.buildInfo});

  final AppBuildInfo? buildInfo;

  @override
  Widget build(BuildContext context) {
    return _AboutCard(
      child: FutureBuilder<AppBuildInfo>(
        future:
            buildInfo != null ? Future.value(buildInfo) : AppBuildInfo.load(),
        builder: (context, snapshot) {
          final info = snapshot.data ??
              const AppBuildInfo(
                versionName: AppBuildInfo.unknownVersion,
                buildNumber: '',
              );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    AppStrings.aboutVersionShort(info.versionName),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (info.buildNumber.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        AppStrings.aboutVersionBuild(info.buildNumber),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: TurnaTheme.textHintColor(context),
                            ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                AppStrings.aboutReleasesNote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TurnaTheme.textHintColor(context),
                    ),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}
